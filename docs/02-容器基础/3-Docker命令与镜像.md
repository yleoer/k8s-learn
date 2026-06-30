# Docker 命令与镜像

镜像是容器交付的核心对象。本文围绕 Docker 环境检查、镜像搜索、拉取、查看、标签管理、删除、导入导出和磁盘占用分析展开，形成一套完整的镜像管理基础流程。

后续记录 Dockerfile、Kubernetes Pod 和镜像仓库时，都会频繁使用这些命令。镜像命令的关键不在于记住所有参数，而在于理解每个命令改变了哪个对象、影响范围有多大，以及如何验证结果。

## 基础检查

开始操作镜像前，先确认 Docker 处于可用状态：

```bash
docker version
docker info
docker ps
docker images
```

`docker version` 重点关注以下字段：

| 字段 | 说明 |
| --- | --- |
| `Client Version` | Docker 客户端版本 |
| `Server Version` | Docker Engine 服务端版本 |
| `containerd` | 底层 containerd 版本 |
| `runc` | 底层 OCI runtime 版本 |
| `OS/Arch` | 操作系统与 CPU 架构 |

`docker info` 重点关注以下字段：

| 字段 | 说明 |
| --- | --- |
| `Containers` | 当前容器数量 |
| `Images` | 本地镜像数量 |
| `Storage Driver` | 镜像与容器层使用的存储驱动 |
| `Logging Driver` | 日志驱动类型 |
| `Cgroup Driver` | cgroup 驱动类型，Kubernetes 节点上通常建议使用 `systemd` |
| `Docker Root Dir` | Docker 数据目录，Linux 默认通常为 `/var/lib/docker` |
| `Registry Mirrors` | 镜像加速器地址 |

如果 Docker 命令无法连接 Daemon，优先检查服务状态与日志：

```bash
sudo systemctl status docker --no-pager
sudo journalctl -u docker -xe --no-pager
```

## 搜索镜像

搜索 Redis 镜像：

```bash
docker search redis
```

输出类似如下：

```text
NAME                   DESCRIPTION                                      STARS     OFFICIAL
redis                  Redis is an open source key-value store that…   14000     [OK]
bitnami/redis          Bitnami Redis Docker Image                      300
redis/redis-stack      Redis Stack with JSON, Search, Timeseries…      250
```

`OFFICIAL [OK]` 表示该镜像为 Docker 官方维护镜像。生产环境选择镜像时，应优先考虑来源可信、维护活跃、版本标签清晰、漏洞扫描结果可接受的镜像。

`docker search` 适合初步发现镜像，但不能代替镜像选型。正式使用前，应查看镜像说明、支持架构、版本策略、环境变量、数据目录和启动方式。注意该命令的 `--stars`、`--automated` 和 `is-automated` 等参数已被移除或不再可靠，搜索和选型时建议结合 Docker Hub 网页或 Harbor 等私有仓库的界面进行综合判断。

## 拉取镜像

拉取明确版本的镜像：

```bash
docker pull redis:8-alpine
docker pull nginx:1.27-alpine
```

不指定 tag 时默认使用 `latest`：

```bash
docker pull nginx
```

这通常等价于：

```bash
docker pull nginx:latest
```

`latest` 不等于最新稳定版本，也不适合作为生产发布依据。实验环境可以偶尔使用 `latest`，但生产部署、故障回滚和发布记录中应使用明确版本标签，必要时记录镜像 digest。

## 查看本地镜像

查看本地镜像列表：

```bash
docker images
docker image ls
```

传统 Docker Engine 输出通常包含 `REPOSITORY`、`TAG`、`IMAGE ID`、`CREATED` 和 `SIZE` 等字段。Docker Engine v29 起全新安装默认启用 containerd image store，较新的 Docker Desktop 也自 v4.34 起默认使用 containerd image store，此时输出可能显示为如下格式：

```text
IMAGE                ID             DISK USAGE   CONTENT SIZE   EXTRA
centos:user          94ce4d5dd91f        204MB             0B
hello-world:latest   e2ac70e7319a       10.1kB             0B
nginx:1.27-alpine    6769dc3a703c       48.2MB             0B
nginx:latest         936fef290c8f        161MB             0B    U
redis:8-alpine       3a02d38405dc        114MB             0B
```

字段含义如下：

| 字段 | 说明 |
| --- | --- |
| `IMAGE` | 镜像名称和标签 |
| `ID` | 镜像短 ID，用于快速识别镜像对象 |
| `DISK USAGE` | 镜像在本机占用的磁盘空间（包含解压后的层数据） |
| `CONTENT SIZE` | containerd content store 中压缩内容对象的大小；当实际存储位置不在本地 Docker image store 时可能显示为 `0B` |
| `EXTRA` | 附加状态标记，`U` 表示镜像正在被容器使用或引用 |

如果希望获得更稳定、便于脚本处理的输出，可以使用 `--format`：

```bash
docker image ls --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}'
```

查看镜像详细信息：

```bash
docker image inspect nginx:1.27-alpine
docker history nginx:1.27-alpine
```

`docker image inspect` 适合查看镜像架构、入口命令、环境变量、工作目录和 RepoDigest；`docker history` 适合观察镜像层构成，辅助分析镜像体积。

## 管理镜像标签

为镜像增加新标签：

```bash
docker tag redis:8-alpine redis:local
docker images | grep redis
```

`docker tag` 不会复制镜像内容，只是为同一个镜像 ID 增加新的引用。删除其中一个标签时，通常只会移除该引用，不会立即删除底层镜像层。

推送到私有仓库前，通常需要按目标仓库地址重新打标签：

```bash
docker tag nginx:1.27-alpine harbor.example.com/base/nginx:1.27-alpine
```

镜像标签建议包含明确语义，例如应用版本、基础系统、构建时间或 Git 提交号。避免在生产部署中使用含义模糊、会频繁移动的标签。

## 删除镜像

删除镜像标签或镜像对象：

```bash
docker rmi redis:local
docker rmi redis:8-alpine
```

如果一个镜像仍有其他标签引用，删除时通常只会显示 `Untagged`，底层镜像层不会被删除。只有当所有标签引用都被移除，并且没有容器继续引用该镜像时，Docker 才能真正释放相关镜像层。

查看悬空镜像：

```bash
docker images -f dangling=true
```

删除悬空镜像：

```bash
docker image prune
docker image prune -f   # 跳过确认提示
```

清理所有未被容器使用的镜像（操作范围更大，执行前应确认）：

```bash
docker image prune -a
```

`docker image prune -a` 范围较大，可能删除以后还会使用的镜像，导致下一次启动服务时重新拉取。生产主机执行前，应先使用 `docker system df -v` 查看对象级磁盘占用和引用关系。

## 导出与导入镜像

导出镜像：

```bash
docker save -o nginx.alpine.tar nginx:1.27-alpine
```

导入镜像：

```bash
docker load -i nginx.alpine.tar
```

`docker save` 与 `docker load` 会保留镜像层和标签信息，适合在离线环境、内网环境或受限网络中传输镜像。它们操作的是镜像，不是容器运行状态。

`docker save` 默认使用 Docker 传统格式，生成 tar 包中保留镜像层和清单。如果希望输出 OCI 格式归档，可使用 `docker save --format oci`。

如果需要导出容器文件系统快照，可以使用 `docker export` 和 `docker import`，但这类方式不会完整保留镜像历史、标签和元数据，不适合作为标准镜像交付方式。
