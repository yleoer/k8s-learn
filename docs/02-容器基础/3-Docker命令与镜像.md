# Docker 命令与镜像

安装 Docker 后，先用 `docker version` 和 `docker info` 确认客户端、服务端、运行时和系统配置，再学习镜像的搜索、拉取、查看、打标签、删除、导出和导入。

## 基础检查命令

```bash
docker version
docker info
docker ps
docker images
```

`docker version` 重点关注：

- Client Version：客户端版本。
- Server Version：Docker Engine 服务端版本。
- containerd：底层 containerd 版本。
- runc：底层 OCI runtime 版本。
- OS/Arch：系统和 CPU 架构。

`docker info` 重点关注：

- Containers：容器数量。
- Images：镜像数量。
- Storage Driver：存储驱动。
- Logging Driver：日志驱动。
- Cgroup Driver：建议使用 `systemd`。
- Docker Root Dir：Docker 数据目录，默认 `/var/lib/docker`。
- Registry Mirrors：镜像加速地址。

如果 Docker 命令无法连接 daemon，优先检查：

```bash
sudo systemctl status docker --no-pager
sudo journalctl -u docker -xe --no-pager
```

## 搜索镜像

```bash
docker search redis
```

示例输出：

```text
NAME                   DESCRIPTION                                      STARS     OFFICIAL
redis                  Redis is an open source key-value store that…   14000     [OK]
bitnami/redis          Bitnami Redis Docker Image                      300
redis/redis-stack      Redis Stack with JSON, Search, Timeseries…      250
```

`OFFICIAL [OK]` 表示官方镜像。生产环境优先选择维护活跃、来源可信、版本明确的镜像。

## 下载镜像

```bash
docker pull redis:8-alpine
docker pull nginx:1.27-alpine
```

不建议生产环境只写：

```bash
docker pull nginx
```

因为它等价于拉取 `nginx:latest`，部署结果可能随着上游标签变化而变化。

## 查看本地镜像

```bash
docker images
docker image ls
```

示例输出：

```text
REPOSITORY   TAG          IMAGE ID       CREATED       SIZE
redis        8-alpine     a1b2c3d4e5f6   2 days ago    35MB
nginx        1.27-alpine  b2c3d4e5f6g7   5 days ago    45MB
alpine       3.20         c3d4e5f6g7h8   2 weeks ago   7.4MB
```

常看字段：

| 字段 | 说明 |
| --- | --- |
| `REPOSITORY` | 镜像仓库名 |
| `TAG` | 镜像标签 |
| `IMAGE ID` | 镜像 ID |
| `CREATED` | 创建时间 |
| `SIZE` | 镜像大小 |

## 更改镜像 tag

```bash
docker tag redis:8-alpine redis:local
docker images | grep redis
```

打 tag 不会复制镜像内容，只是给同一个镜像 ID 增加一个引用。

推送到私有仓库前也常需要重新打 tag：

```bash
docker tag nginx:1.27-alpine harbor.example.com/base/nginx:1.27-alpine
```

## 删除镜像

```bash
docker rmi redis:local
docker rmi redis:8-alpine
```

如果一个镜像还有其它 tag 引用，删除时通常只会 `Untagged`。当所有引用都删除且没有容器使用时，镜像层才会真正 `Deleted`。

查看悬空镜像：

```bash
docker images -f dangling=true
```

删除悬空镜像：

```bash
docker image prune
docker image prune -f
```

删除所有当前没有被容器使用的镜像要更谨慎：

```bash
docker image prune -a
```

## 导出和导入镜像

```bash
docker save -o nginx.alpine.tar nginx:1.27-alpine
docker load -i nginx.alpine.tar
```

`docker save/load` 保留镜像层和 tag，适合离线迁移镜像。

## 本节回顾

- `docker version` 看客户端、服务端、containerd、runc 版本。
- `docker info` 看存储、日志、cgroup、数据目录和镜像加速配置。
- 镜像管理围绕 search、pull、images、tag、rmi、save、load 展开。
- 生产环境优先使用明确版本 tag，并选择可信镜像来源。

