# Docker 容器管理

容器是由镜像启动出来的运行实例。本节整理容器启动、查看、端口映射和详细信息查看。

## 启动容器

前台启动，退出后自动删除：

```bash
docker run -it --rm nginx:alpine sh
```

后台启动：

```bash
docker run -d nginx:latest
```

指定名字：

```bash
docker run -d --name web1 nginx:latest
```

映射端口：

```bash
docker run -d --name web2 -p 8081:80 nginx:latest
```

`-p 8081:80` 表示把宿主机 `8081` 端口映射到容器内 `80` 端口。

## 查看容器

```bash
docker ps
docker ps -q
docker ps -a
```

## 查看容器详细信息

```bash
docker inspect <container-id-or-name>
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
docker stop <container-id-or-name>
docker kill <container-id-or-name>
```
