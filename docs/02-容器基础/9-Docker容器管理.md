# Docker 容器管理

容器是由镜像启动出来的运行实例。本节整理容器启动、查看、端口映射和详细信息查看。

## 启动容器

前台启动，退出后自动删除：

```bash
docker run -it --rm nginx:alpine sh
```

后台启动并映射端口：

```bash
docker run -d --name web1 -p 8080:80 nginx:alpine
```

映射端口：

```bash
docker run -d --name web2 -p 8081:80 nginx:latest
```

`-p 8081:80` 表示把宿主机 `8081` 端口映射到容器内 `80` 端口。

这里使用 `latest` 只是演示默认标签的效果。生产环境应使用明确版本，例如 `nginx:1.27-alpine`，否则同一条命令在不同时间可能拉到不同镜像，回滚和问题定位都会变困难。

## 限制容器资源

生产环境建议为容器设置资源上限，避免单个容器耗尽宿主机资源：

```bash
docker run -d --name web3 \
  --memory 256m \
  --cpus 0.5 \
  -p 8082:80 nginx:alpine
```

常用资源限制参数：

| 参数 | 作用 |
| --- | --- |
| `--memory` / `-m` | 内存上限，如 `256m`、`1g` |
| `--cpus` | CPU 核心数上限，如 `0.5`、`2` |
| `--memory-swap` | 内存 + swap 总上限 |

设置资源限制后，可以在 `docker stats` 中实时查看资源用量：

```bash
docker stats web3
```

<details>
<summary>docker stats 示例</summary>

```text
CONTAINER ID   NAME      CPU %     MEM USAGE / LIMIT     MEM %     NET I/O
a1b2c3d4e5f6   web3      0.15%     12.5MiB / 256MiB      4.88%     1.2kB / 0B
```

</details>

这些参数与 Kubernetes Pod 中的 `resources.limits` 和 `resources.requests` 概念一致，提前理解有助于后续 K8s 资源管理。

## 查看容器

```bash
docker ps
docker ps -q
docker ps -a
```

<details>
<summary>docker ps 示例</summary>

```text
$ docker ps
CONTAINER ID   IMAGE           COMMAND                  CREATED         STATUS         PORTS                  NAMES
a1b2c3d4e5f6   nginx:alpine    "/docker-entrypoint.…"   5 minutes ago   Up 5 minutes   0.0.0.0:8080->80/tcp   web1
```

</details>

## 查看容器详细信息

```bash
docker inspect web1
```

常看字段：

- `State.Status`：容器状态
- `State.ExitCode`：退出码
- `Config.Image`：使用的镜像
- `Config.Cmd`：默认命令
- `NetworkSettings.Networks`：网络、IP、网关
- `Mounts`：挂载信息
- `HostConfig.PortBindings`：端口映射

## 停止容器

```bash
docker stop web1
docker kill web1
```
