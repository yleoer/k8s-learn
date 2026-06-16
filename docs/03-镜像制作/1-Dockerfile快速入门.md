# Dockerfile 快速入门

Dockerfile 是一个文本文件，用于定义 Docker 镜像的构建步骤。它由一系列指令组成，每个指令都会参与生成镜像层或镜像元数据。

## 常用指令

| 指令 | 作用 |
| --- | --- |
| `FROM` | 指定基础镜像 |
| `RUN` | 构建阶段执行 shell 命令 |
| `LABEL` | 添加镜像元数据 |
| `ENV` | 设置运行时环境变量 |
| `ADD` | 复制文件到镜像，支持自动解压本地 tar 包 |
| `COPY` | 复制文件或目录到镜像 |
| `WORKDIR` | 设置工作目录 |
| `USER` | 设置运行用户 |
| `EXPOSE` | 声明容器监听端口 |
| `HEALTHCHECK` | 设置容器健康检查方式 |
| `CMD` | 设置容器默认命令，可被覆盖 |
| `ENTRYPOINT` | 设置容器入口命令 |
| `ARG` | 设置构建参数 |

`MAINTAINER` 已不推荐使用，建议用 `LABEL maintainer="..."` 替代。

## 第一个 Dockerfile

```dockerfile
FROM nginx:alpine
COPY ./html /usr/share/nginx/html
EXPOSE 80
```

构建镜像：

```bash
docker build -t nginx:demo .
```

<details>
<summary>docker build 示例输出</summary>

```text
$ docker build -t nginx:demo .
[+] Building 0.6s (7/7) FINISHED
 => [internal] load build definition from Dockerfile
 => => transferring dockerfile: 120B
 => [internal] load .dockerignore
 => [internal] load metadata for docker.io/library/nginx:alpine
 => [1/2] FROM docker.io/library/nginx:alpine
 => [internal] load build context
 => => transferring context: 156B
 => [2/2] COPY ./html /usr/share/nginx/html
 => exporting to image
 => => naming to docker.io/library/nginx:demo
```

</details>

运行验证：

```bash
docker run -d --name nginx-demo -p 8080:80 nginx:demo
curl http://127.0.0.1:8080
```

## FROM：选择基础镜像

`FROM` 必须是 Dockerfile 的第一条有效构建指令。它决定镜像的系统环境、包管理器、默认 shell 和基础文件系统。

```dockerfile
FROM alpine:3.20
```

建议：

- 使用明确 tag，避免依赖 `latest`。
- 优先选择官方镜像或可信镜像。
- 生产镜像尽量选择体积小、维护活跃的基础镜像。

## RUN：执行构建命令

```dockerfile
FROM alpine:3.20
LABEL maintainer="yleoer"
RUN adduser -D yleoer
```

构建并验证：

```bash
docker build -t alpine:user .
docker run -it --rm alpine:user cat /etc/passwd
```

## 构建缓存与指令顺序

Docker 构建时会按指令顺序使用缓存。某一层发生变化后，后续层缓存通常都会失效。

适合放前面的内容：变化少的系统依赖安装、基础工具、用户创建。

适合放后面的内容：应用代码、频繁变化的配置、构建产物。

多个 `RUN` 会产生更多层。安装软件时合并命令并清理缓存：

```dockerfile
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
```

## LABEL：镜像元数据

`LABEL` 用来给镜像添加元数据，例如维护者、版本、源码地址、构建时间等。

```dockerfile
FROM alpine:3.20
LABEL maintainer="yleoer" version="demo"
LABEL multiple="true"
```

```bash
docker build -t alpine:label .
docker inspect alpine:label | grep Labels -A 20
```

推荐的 OCI 标准标签：

```dockerfile
LABEL maintainer="platform@example.com"
LABEL org.opencontainers.image.title="demo-app"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.source="https://example.com/repo/demo-app"
LABEL org.opencontainers.image.description="Demo application image"
```

## HEALTHCHECK：容器健康检查

`HEALTHCHECK` 告诉 Docker 如何检查容器是否健康。没有它时 Docker 只能判断进程是否存活，无法知道应用是否正常响应。

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD curl -f http://127.0.0.1:80/healthz || exit 1
```

| 参数 | 含义 | 默认值 |
| --- | --- | --- |
| `--interval` | 检查间隔 | 30s |
| `--timeout` | 单次检查超时 | 30s |
| `--retries` | 连续失败次数阈值 | 3 |
| `--start-period` | 容器启动后等待时间 | 0s |

在 `docker ps` 中可以看到健康状态：

```bash
$ docker ps
CONTAINER ID   IMAGE         STATUS                    PORTS
a1b2c3d4e5f6   app:v1.0.0    Up 10 minutes (healthy)   0.0.0.0:8080->8080/tcp
```

Kubernetes 中的 Pod 健康检查（liveness / readiness / startup probe）与 Docker HEALTHCHECK 的思路一致，但 Kubernetes 不会自动读取镜像里的 `HEALTHCHECK` 并转换成探针。部署到 Kubernetes 时，仍然需要在 Pod 或 Deployment 中显式配置 `livenessProbe`、`readinessProbe` 或 `startupProbe`。

## 编写原则

- 优先选择明确版本的基础镜像。
- 指令顺序要考虑缓存复用。
- 不把密码、token 等敏感信息写进镜像。
- 一个镜像只负责一个主要进程。
- 构建产物尽量小、依赖尽量少。
- 为生产镜像添加 HEALTHCHECK。

## 生产镜像安全检查

| 检查项 | 建议 |
| --- | --- |
| 基础镜像 | 使用官方或可信来源，固定版本 tag，定期升级补丁 |
| 运行用户 | 默认使用非 root 用户，只给应用必要目录写权限 |
| 构建上下文 | 使用 `.dockerignore` 排除 `.git`、日志、缓存、测试产物和本地配置 |
| 敏感信息 | 不把密码、Token、私钥、kubeconfig 写入镜像层 |
| 依赖安装 | 安装后清理包管理器缓存，减少无关工具 |
| 健康检查 | Docker 单机可使用 `HEALTHCHECK`，Kubernetes 中显式配置 probes |
| 日志输出 | 输出到 stdout/stderr，便于 Docker、containerd 和 Kubernetes 收集 |
| 漏洞治理 | 发布前使用 Harbor、Trivy 等工具扫描镜像漏洞 |
