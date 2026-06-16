# Docker 部署服务通用步骤

部署一个 Docker 服务时，不建议只记一条 `docker run` 命令，而应该形成一套固定检查流程。

## 1. 确认镜像

```bash
docker search nginx
docker pull nginx:alpine
docker images | grep nginx
```

确认镜像来源可信、版本明确、架构匹配。

## 2. 规划端口、数据和配置

部署前先明确：

- 容器监听端口是什么
- 宿主机要暴露哪个端口
- 是否需要挂载配置文件
- 是否需要持久化数据
- 是否需要环境变量
- 是否需要重启策略
- 内存和 CPU 上限是多少

## 3. 启动容器

```bash
docker run -d \
  --name nginx-demo \
  --restart unless-stopped \
  --memory 256m \
  --cpus 0.5 \
  -p 8080:80 \
  -v "$PWD/html:/usr/share/nginx/html" \
  nginx:alpine
```

## 4. 验证服务

```bash
docker ps
docker logs --tail 50 nginx-demo
curl http://127.0.0.1:8080
```

## 5. 排查问题

```bash
docker inspect nginx-demo
docker exec -it nginx-demo sh
sudo ss -lntup | grep 8080
```

常见问题：端口被占用、挂载路径错误、容器内应用启动失败、镜像架构不匹配、文件权限不足。

## 6. 清理服务

```bash
docker stop nginx-demo
docker rm nginx-demo
docker rmi nginx:alpine
```

## 本章回顾

完成本章后，你应该具备以下能力：

- 区分物理机、虚拟机、容器的运行方式和适用场景。
- 理解镜像、容器、镜像仓库的关系和镜像地址的组成部分。
- 了解 Docker 架构（Client、Daemon、containerd、runc）和命令执行链路。
- 掌握 Docker 基础命令：version、info、search、pull、images、tag、rmi。
- 熟练操作容器：run、ps、inspect、stop、logs、exec、rm、prune。
- 使用 bind mount 和 volume 实现数据持久化，使用 docker cp 拷贝文件。
- 理解 Docker 与 Kubernetes 运行时（CRI、containerd）的关系。
- 按标准六步流程部署和验证一个容器化服务。
- 为容器设置 CPU 和内存限制，理解与 K8s 资源管理的对应关系。

下一步进入第 03 章，学习使用 Dockerfile 构建自己的镜像。
