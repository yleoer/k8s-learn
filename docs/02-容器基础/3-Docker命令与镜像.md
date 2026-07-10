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

这四条命令分别验证客户端与服务端是否连通、运行环境配置是否符合预期、容器与镜像对象是否可见。`docker version` 和 `docker info` 的输出结构、常见字段含义，以及无法连接 Daemon 时的排查步骤，已在上一篇 [Docker 架构与运行时](./2-Docker架构与运行时.md) 中说明，此处不再重复。

## 搜索镜像

搜索 Redis 镜像：

```bash
docker search redis
```

::: details 输出类似如下

```text
NAME                   DESCRIPTION                                      STARS     OFFICIAL
redis                  Redis is an open source key-value store that…   14000     [OK]
bitnami/redis          Bitnami Redis Docker Image                      300
redis/redis-stack      Redis Stack with JSON, Search, Timeseries…      250
```

:::

`OFFICIAL [OK]` 表示该镜像为 Docker 官方维护镜像。生产环境选择镜像时，应优先考虑来源可信、维护活跃、版本标签清晰、漏洞扫描结果可接受的镜像。

`docker search` 适合初步发现镜像，但不能代替镜像选型。正式使用前，应查看镜像说明、支持架构、版本策略、环境变量、数据目录和启动方式。注意该命令的 `--stars`、`--automated` 和 `is-automated` 等参数已被移除或不再可靠，搜索和选型时建议结合 Docker Hub 网页或 Harbor 等私有仓库的界面进行综合判断。

## 拉取镜像

拉取明确版本镜像的命令复用前文[不建议依赖 latest](./1-容器核心概念.md#不建议依赖-latest)中的示例。

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

Docker Engine v28 及更早版本，输出通常包含 `REPOSITORY`、`TAG`、`IMAGE ID`、`CREATED` 和 `SIZE` 等字段。Docker Engine v29 起，CLI 默认改用新的输出格式。

::: details 新版输出类似如下

```text
IMAGE                ID             DISK USAGE   CONTENT SIZE   EXTRA
centos:user          94ce4d5dd91f        204MB             0B
hello-world:latest   e2ac70e7319a       10.1kB             0B
nginx:1.31-alpine    6769dc3a703c       48.2MB             0B
nginx:latest         936fef290c8f        161MB             0B    U
redis:8.8-alpine       3a02d38405dc        114MB             0B
```

:::

字段含义如下：

| 字段             | 说明                                               |
|----------------|--------------------------------------------------|
| `IMAGE`        | 镜像名称和标签                                          |
| `ID`           | 镜像短 ID，用于快速识别镜像对象                                |
| `DISK USAGE`   | 镜像在本机占用的磁盘空间（包含解压后的层数据）                          |
| `CONTENT SIZE` | 本地保留的镜像压缩内容（推送、拉取时传输的 blob）大小；本地未保留压缩内容时显示为 `0B` |
| `EXTRA`        | 附加状态标记，`U` 表示镜像正在被容器使用或引用                        |

如果希望获得更稳定、便于脚本处理的输出，可以使用 `--format`：

```bash
docker image ls --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}'
```

查看镜像详细信息：

```bash
docker image inspect nginx:1.31-alpine
docker history nginx:1.31-alpine
```

`docker image inspect` 适合查看镜像架构、入口命令、环境变量、工作目录和 RepoDigest；`docker history` 适合观察镜像层构成，辅助分析镜像体积。

## 管理镜像标签

为镜像增加新标签：

```bash
docker tag redis:8.8-alpine redis:local
docker images | grep redis
```

`docker tag` 不会复制镜像内容，只是为同一个镜像 ID 增加新的引用。删除其中一个标签时，通常只会移除该引用，不会立即删除底层镜像层。

推送到私有仓库前，通常需要按目标仓库地址重新打标签：

```bash
docker tag nginx:1.31-alpine harbor.example.com/base/nginx:1.31-alpine
```

镜像标签建议包含明确语义，例如应用版本、基础系统、构建时间或 Git 提交号。避免在生产部署中使用含义模糊、会频繁移动的标签。

## 删除镜像

删除镜像标签或镜像对象：

```bash
docker rmi redis:local
docker rmi redis:8.8-alpine
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
docker save -o nginx.alpine.tar nginx:1.31-alpine
```

导入镜像：

```bash
docker load -i nginx.alpine.tar
```

`docker save` 与 `docker load` 会保留镜像层和标签信息，适合在离线环境、内网环境或受限网络中传输镜像。它们操作的是镜像，不是容器运行状态。

Docker Engine v25 起，`docker save` 生成的 tar 包采用 OCI image layout 布局，同时保留 `manifest.json` 等文件兼容传统 Docker 格式，无需额外参数。Docker Engine v28 起，在启用 containerd image store 的环境中，`docker save` 与 `docker load` 支持 `--platform` 参数，可以只导出或导入多平台镜像中的指定平台。

如果需要导出容器文件系统快照，可以使用 `docker export` 和 `docker import`，但这类方式不会完整保留镜像历史、标签和元数据，不适合作为标准镜像交付方式。
