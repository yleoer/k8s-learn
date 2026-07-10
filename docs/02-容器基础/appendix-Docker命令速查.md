# Docker 命令速查

本附录汇总 Docker 实验和服务部署过程中最常用的命令。正文按概念和原理展开，附录按实际操作场景组织，便于在实验、排障和回看时快速查找。

## 环境检查

查看 Docker 版本、运行环境和当前对象：

```bash
docker version
docker info
docker ps
docker images
docker volume ls
docker network ls
```

Linux 主机上排查 Docker 服务：

```bash
sudo systemctl status docker --no-pager
sudo journalctl -u docker -xe --no-pager
```

## 镜像命令

搜索与拉取镜像：

```bash
docker search nginx
docker pull nginx:1.31-alpine
docker pull redis:8.8-alpine
```

查看本地镜像：

```bash
docker images
docker image ls
docker images nginx
docker image ls --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}'
```

查看镜像详情：

```bash
docker image inspect nginx:1.31-alpine
docker history nginx:1.31-alpine
docker image inspect nginx:1.31-alpine --format '{{.Architecture}}'
```

打标签与删除镜像：

```bash
docker tag nginx:1.31-alpine nginx:demo
docker tag nginx:1.31-alpine harbor.example.com/base/nginx:1.31-alpine
docker rmi nginx:demo
docker image prune
```

离线导入导出：

```bash
docker save -o nginx.alpine.tar nginx:1.31-alpine
docker load -i nginx.alpine.tar
```

## 容器运行

前台运行临时容器：

```bash
docker run --rm -it nginx:1.31-alpine sh
```

后台运行服务容器：

```bash
docker run -d \
  --name nginx-demo \
  --restart unless-stopped \
  --memory 256m \
  --cpus 0.5 \
  -p 8080:80 \
  -v "$PWD/html:/usr/share/nginx/html" \
  nginx:1.31-alpine
```

常用参数如下：

| 参数                         | 作用                      |
|----------------------------|-------------------------|
| `-d`                       | 后台运行容器                  |
| `--name`                   | 指定容器名称                  |
| `--restart unless-stopped` | Docker 启动后自动拉起容器，手动停止除外 |
| `--memory`                 | 限制容器可用内存                |
| `--cpus`                   | 限制容器可用 CPU              |
| `-p`                       | 端口映射，格式为宿主机端口:容器端口      |
| `-v`                       | 挂载文件、目录或 volume         |
| `-e`                       | 设置环境变量                  |

## 查看与进入

查看容器列表：

```bash
docker ps
docker ps -a
docker ps --filter name=nginx-demo
docker ps --filter status=exited
```

查看日志：

```bash
docker logs nginx-demo
docker logs --tail 50 nginx-demo
docker logs -f nginx-demo
docker logs --since 10m --timestamps nginx-demo
```

进入容器：

```bash
docker exec -it nginx-demo sh
docker exec nginx-demo nginx -v
docker exec nginx-demo env
```

查看容器详情与资源占用：

```bash
docker inspect nginx-demo
docker stats nginx-demo
docker top nginx-demo
```

## 挂载与文件

使用 bind mount 挂载宿主机目录：

```bash
mkdir -p ./html
echo 'hello nginx' > ./html/index.html
docker run -d --name web -p 8080:80 -v "$PWD/html:/usr/share/nginx/html" nginx:1.31-alpine
```

使用 named volume：

```bash
docker volume create nginx-data
docker run -d --name web-volume -v nginx-data:/usr/share/nginx/html nginx:1.31-alpine
docker volume inspect nginx-data
```

复制文件：

```bash
docker cp install.sh nginx-demo:/tmp/install.sh
docker cp nginx-demo:/var/log/nginx/access.log ./access.log
```

备份和恢复 volume：

```bash
mkdir -p ./backup
docker run --rm -v nginx-data:/data -v "$PWD/backup:/backup" alpine:3.23 tar czf /backup/nginx-data.tgz -C /data .
docker volume create nginx-data-restore
docker run --rm -v nginx-data-restore:/data -v "$PWD/backup:/backup" alpine:3.23 tar xzf /backup/nginx-data.tgz -C /data
```

## 网络与 Compose

管理容器网络：

```bash
docker network ls
docker network create app-net
docker network inspect app-net
docker network connect app-net nginx-demo
docker network disconnect app-net nginx-demo
docker network prune
```

指定网络运行容器并按名称互访：

```bash
docker run -d --name web --network app-net nginx:1.31-alpine
docker run --rm --network app-net busybox:1.38 wget -qO- http://web
```

Compose 项目管理：

```bash
docker compose up -d
docker compose ps
docker compose logs -f web
docker compose exec web sh
docker compose config
docker compose down
```

## 验证与排障

验证服务访问：

```bash
docker ps --filter name=nginx-demo
docker logs --tail 50 nginx-demo
curl http://127.0.0.1:8080
```

查看端口监听：

```bash
sudo ss -lntup | grep 8080
```

排查容器启动失败：

```bash
docker ps -a
docker logs nginx-demo
docker inspect nginx-demo
docker inspect nginx-demo --format '{{.State.ExitCode}}'
docker exec -it nginx-demo sh
```

查看磁盘占用：

```bash
docker system df
docker system df -v
```

## 停止与清理

停止与删除容器：

```bash
docker stop nginx-demo
docker kill nginx-demo
docker rm nginx-demo
docker rm -f nginx-demo
```

删除镜像：

```bash
docker rmi nginx:1.31-alpine
docker image prune
docker image prune -a
```

清理未使用资源：

```bash
docker container prune
docker volume prune       # 默认只清理未被使用的匿名卷
docker volume prune -a    # 包含命名卷，可能删除业务数据
docker network prune
docker system prune
docker system prune -a
```

`docker system prune` 会删除停止的容器、未使用网络、悬空镜像和构建缓存。生产环境执行前应先使用 `docker system df` 或 `docker system df -v` 确认影响范围，避免误删仍需保留的镜像、缓存或数据卷。

## 常见问题

| 问题        | 分析                                                                                            |
|-----------|-----------------------------------------------------------------------------------------------|
| 端口被占用     | 宿主机端口只能被一个进程监听。遇到 `bind: address already in use` 时，先用 `sudo ss -lntup` 查看端口占用，再更换宿主机端口或停止已有服务 |
| 挂载路径错误    | bind mount 使用宿主机真实路径，路径写错或目录为空时，容器内看到的内容也会异常。应先确认宿主机路径存在，再用 `docker inspect` 查看实际挂载结果         |
| 容器内应用启动失败 | 镜像拉取成功不代表应用可以正常启动。应通过 `docker ps -a` 查看退出状态，再用 `docker logs` 查看应用报错                           |
| 镜像架构不匹配   | x86_64、arm64 等架构不一致时，容器可能启动失败或运行异常。可用 `docker image inspect` 查看镜像架构，并确认主机 CPU 架构是否匹配          |
| 文件权限不足    | 容器进程可能不是 root 用户，挂载文件或目录权限不足会导致读取、写入失败。应检查宿主机文件权限、属主属组，以及容器内进程运行用户                            |
| 环境变量缺失    | 很多镜像依赖环境变量完成初始化，例如密码、数据目录或启动模式。应对照镜像说明补齐 `-e` 参数，并用 `docker inspect` 确认变量是否传入                 |
| 宿主机防火墙未放行 | 容器启动正常但外部无法访问时，问题可能在宿主机防火墙或云安全组。应先本机 `curl 127.0.0.1:<port>` 验证，再检查防火墙规则和安全组策略                |
