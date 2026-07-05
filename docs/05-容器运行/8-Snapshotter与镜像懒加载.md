# Snapshotter 与镜像懒加载

[节点镜像缓存与垃圾回收](./6-节点镜像缓存与垃圾回收.md) 记录了镜像在节点上的存储与回收。镜像层被拉取后还需要解包成容器可用的根文件系统，这一层由 containerd 的 snapshotter 负责。snapshotter 的选型决定文件系统行为，远程 snapshotter 则进一步改变“先拉完镜像再启动”的模式，实现镜像懒加载。

## snapshotter 职责

snapshotter 管理容器文件系统的快照：把镜像层逐层组装为只读快照，并在容器启动时在其上创建可写层。它对应 Docker 中 graphdriver 的角色，但设计上不感知镜像和容器，只提供快照的准备与提交，因此可以独立替换。

查看当前可用的 snapshotter 插件：

```bash
sudo ctr plugins ls | grep snapshotter
```

CRI 使用的 snapshotter 在 `/etc/containerd/config.toml` 中配置，配置段路径随大版本不同：

```toml [containerd 2.x]
[plugins.'io.containerd.cri.v1.images']
  snapshotter = "overlayfs"
```

```toml [containerd 1.x]
[plugins."io.containerd.grpc.v1.cri".containerd]
  snapshotter = "overlayfs"
```

## 内置 snapshotter 选型

| snapshotter | 机制 | 适用场景 |
| --- | --- | --- |
| `overlayfs` | 基于内核 OverlayFS 的联合挂载 | 默认选择，等价于 Docker 的 overlay2 定位 |
| `native` | 逐层完整复制文件 | 类似 Docker vfs，无 CoW，占用大，仅特殊排障场景 |
| `blockfile` | 每个快照一个块文件 | 虚拟机或需要块设备语义的场景 |
| `devmapper` | device-mapper thin-pool 块设备 | 需要预先创建 thin-pool，块级隔离需求 |
| `btrfs` / `zfs` | 文件系统原生快照 | 插件数据目录本身位于对应文件系统时 |
| `erofs` | EROFS 只读文件系统 | containerd 2.1 起内置，只读层更紧凑 |
| `fuse-overlayfs` | 用户态 OverlayFS | 仅旧内核（5.11 之前）的 rootless 场景需要 |

几个版本相关的事实：aufs snapshotter 已在 containerd 2.0 移除；zfs 代码在独立仓库维护，但默认编译进 Linux 官方二进制；`btrfs`、`zfs` 要求插件根目录（如 `/var/lib/containerd/io.containerd.snapshotter.v1.btrfs`）挂载为对应文件系统，否则插件不可用。对绝大多数 Kubernetes 节点，`overlayfs` 是不需要更换的默认答案，替换动机通常来自懒加载。

## 镜像懒加载

容器冷启动的主要耗时在镜像拉取。FAST '16 论文的研究数据显示：拉取占容器启动时间的约 76%，而实际只有约 6.4% 的镜像数据会被读取，stargz 与 SOCI 等项目都以该论文作为懒加载的出发点。懒加载（lazy pulling）的思路是不等镜像完整下载，容器先启动，文件访问时再按需从 Registry 读取对应数据块。

实现载体是远程 snapshotter：快照的内容不完全在本地，缺失部分由 snapshotter 在运行期通过 HTTP Range 请求从 Registry 补齐。主要方案：

| 方案 | 项目 | 镜像处理 | 机制要点 |
| --- | --- | --- | --- |
| eStargz | containerd/stargz-snapshotter | 需转换为 eStargz 格式 | 格式兼容 OCI，普通运行时可正常运行同一镜像，支持启动文件预取 |
| Nydus | containerd/nydus-snapshotter | RAFS 格式需转换；zran 模式可直接懒加载 OCI 镜像 | chunk 级内容寻址，FUSE、virtiofs 或内核 EROFS 后端 |
| overlaybd | containerd/accelerated-container-image | 需转换为块设备格式 | 提供块设备接口，另有 turboOCI 免转换模式 |
| SOCI | awslabs/soci-snapshotter | v2 索引需 `soci convert` 轻量转换，层数据与原镜像复用 | 独立索引描述懒加载，无索引时自动回退整体拉取 |

> [!NOTE]
> SOCI 早期版本以“不改镜像、只附加索引”著称，但自 v0.10.0 起默认使用 Index Manifest v2，需要执行轻量转换生成强关联的镜像与索引；仅附加索引的 v1 模式默认禁用。引用旧资料时需要注意这一变化。

## 启用方式

远程 snapshotter 以独立进程运行，containerd 通过 proxy plugin 接入。以 stargz 为例，节点上需要运行 stargz-snapshotter 守护进程（二进制名 `containerd-stargz-grpc`），并在 containerd 配置中注册：

```toml
[proxy_plugins]
  [proxy_plugins.stargz]
    type = "snapshot"
    address = "/run/containerd-stargz-grpc/containerd-stargz-grpc.sock"
```

再把 CRI 的 snapshotter 指向它，并允许把镜像注解传递给远程 snapshotter：

```toml [containerd 1.x]
[plugins."io.containerd.grpc.v1.cri".containerd]
  snapshotter = "stargz"
  disable_snapshot_annotations = false
```

两个常见问题需要记录：

- `disable_snapshot_annotations` 默认值为 `true`，不显式关闭时远程 snapshotter 收不到镜像信息，懒加载不会生效，表现为配置了 snapshotter 但行为与 overlayfs 相同。
- containerd 2.1 起 CRI 默认改用 transfer service 拉取镜像，检测到 `disable_snapshot_annotations = false` 等冲突配置时会自动回退本地拉取路径（等效于设置 `use_local_image_pull = true`）；升级前应核对所用 snapshotter 项目的适配说明。

containerd 1.7 起还支持按 runtime 指定 snapshotter（如仅 Kata 使用特定 snapshotter），该能力目前仍标注为实验特性。

## 收益与代价

懒加载适合冷启动敏感且镜像巨大的场景：AI 推理镜像、FaaS 弹性扩容、批量节点扩容时的镜像风暴。代价同样明确：

- 运行期依赖 Registry 可用性：文件首次访问要经过网络，Registry 抖动会转化为应用的 I/O 延迟甚至错误，而不再只是启动失败。
- Registry 必须支持 HTTP Range 请求，SOCI 还对 manifest 特性有额外要求。
- 镜像需要转换或生成索引，发布流水线增加一个环节，转换后制品的存储与同步也要纳入管理。
- 排障链路变长：文件读取问题可能来自 snapshotter 进程、索引缺失或网络，而不只是本地磁盘。

长驻服务、镜像本身较小或节点镜像缓存命中率高的集群，默认的 overlayfs 加上镜像预热往往比引入懒加载更划算。

## 记录要点

- snapshotter 决定镜像层如何变成容器根文件系统，默认 `overlayfs`，无特殊诉求不更换。
- 懒加载的本质是把拉取成本从启动期转移到运行期，评估时先确认业务能接受运行期的 Registry 依赖。
- 启用远程 snapshotter 时，`disable_snapshot_annotations = false` 是最容易遗漏的开关。
- eStargz、Nydus、overlaybd、SOCI 都处于活跃维护状态，选型时优先验证与当前 containerd 版本和 Registry 的兼容性。

## 参考

- [containerd snapshotters](https://github.com/containerd/containerd/blob/main/docs/snapshotters/README.md)
- [containerd CRI config](https://github.com/containerd/containerd/blob/main/docs/cri/config.md)
- [stargz-snapshotter](https://github.com/containerd/stargz-snapshotter)
- [nydus-snapshotter](https://github.com/containerd/nydus-snapshotter)
- [accelerated-container-image (overlaybd)](https://github.com/containerd/accelerated-container-image)
- [soci-snapshotter](https://github.com/awslabs/soci-snapshotter)
