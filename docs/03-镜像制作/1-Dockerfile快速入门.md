# Dockerfile 快速入门

Dockerfile 是一个纯文本文件，按行声明构建步骤。构建指令会生成文件系统层或镜像配置元数据，理解指令作用和顺序，是写好 Dockerfile 的前提。

## 常用指令

| 指令            | 作用                                    |
|---------------|---------------------------------------|
| `FROM`        | 指定基础镜像并创建构建阶段，通常是第一条指令；仅 `ARG` 可在其前声明 |
| `RUN`         | 在构建阶段执行命令，产生新的镜像层                     |
| `LABEL`       | 添加镜像元数据（维护者、版本、源码地址等）                 |
| `ENV`         | 设置环境变量，构建阶段和运行阶段均可见                   |
| `ARG`         | 设置构建参数，仅在构建阶段可见                       |
| `COPY`        | 复制文件或目录到镜像                            |
| `ADD`         | 复制文件到镜像，额外支持自动解压本地 tar 包和从远程 URL 获取内容 |
| `WORKDIR`     | 设置后续指令的工作目录                           |
| `USER`        | 设置当前阶段后续指令和容器运行时使用的用户                 |
| `EXPOSE`      | 声明容器计划监听的端口（仅文档作用，不实际发布端口）            |
| `HEALTHCHECK` | 定义检查容器是否健康的方式                         |
| `CMD`         | 容器启动时的默认命令，可被 `docker run` 覆盖         |
| `ENTRYPOINT`  | 容器入口命令，`CMD` 的内容会作为它的默认参数             |

> [!NOTE]
> `MAINTAINER` 已废弃，改用 `LABEL maintainer="..."`。

## 第一个镜像

从最简单的 Dockerfile 开始——复制静态文件到 nginx 镜像，并声明容器内应用计划监听的端口。

先准备一个静态文件目录，确保构建上下文中存在 `COPY` 指令要复制的源路径：

```bash
mkdir -p html
echo '<h1>Hello nginx</h1>' > html/index.html
```

```dockerfile [Dockerfile]
FROM nginx:1.27-alpine
COPY ./html /usr/share/nginx/html
EXPOSE 80
```

构建镜像：

```bash
docker build -t nginx:demo .
```

::: details docker build 输出类似如下

```text
$ docker build -t nginx:demo .
[+] Building 2.1s (7/7) FINISHED                                                                                                  docker:default
 => [internal] load build definition from Dockerfile                                                                                        0.0s
 => => transferring dockerfile: 99B                                                                                                         0.0s
 => [internal] load metadata for docker.io/library/nginx:1.27-alpine                                                                        2.0s
 => [internal] load .dockerignore                                                                                                           0.0s
 => => transferring context: 2B                                                                                                             0.0s
 => [internal] load build context                                                                                                           0.0s
 => => transferring context: 91B                                                                                                            0.0s
 => CACHED [1/2] FROM docker.io/library/nginx:1.27-alpine@sha256:<digest>                                                                   0.0s
 => [2/2] COPY ./html /usr/share/nginx/html                                                                                                 0.0s
 => exporting to image                                                                                                                      0.0s
 => => exporting layers                                                                                                                     0.0s
 => => writing image sha256:<image-id>                                                                                                      0.0s
 => => naming to docker.io/library/nginx:demo                                                                                               0.0s
```

:::

运行验证：

```bash
docker run -d --name nginx-demo -p 8080:80 nginx:demo
curl http://127.0.0.1:8080
```

每次执行 `docker build`，Docker 会把命令指定的目录（示例末尾的 `.`）作为构建上下文（build context）发送给 daemon；Dockerfile 默认位于上下文根目录，也可以用 `-f` 指定其他路径。上下文目录中的所有文件默认都会被打包发送，因此需要 `.dockerignore` 排除无关内容（详见 [镜像分层与体积优化](./4-镜像分层与体积优化.md)）。

## EXPOSE：声明监听端口

`EXPOSE` 表示镜像作者认为容器运行时会监听哪些端口。它会写入镜像元数据，方便使用者、工具或 `docker inspect` 查看，但不会把端口发布到宿主机。

端口发布发生在 `docker run` 阶段：

| 写法        | 作用                                                    |
|-----------|-------------------------------------------------------|
| `EXPOSE` | Dockerfile 中的文档约定，只声明容器计划监听的端口，不发布端口              |
| `-p`      | 把指定容器端口发布到宿主机指定端口，例如 `-p 8080:80`                 |
| `-P`      | 把镜像中所有 `EXPOSE` 声明的端口发布到宿主机随机高位端口                 |

可以用前文构建的 `nginx:demo` 验证三者差异。只声明 `EXPOSE 80` 时，镜像元数据中能看到端口声明：

```bash
docker inspect nginx:demo --format '{{json .Config.ExposedPorts}}'
```

::: details 输出类似如下

```text
{"80/tcp":{}}
```

:::

但仅运行容器不会产生宿主机端口映射：

```bash
docker run -d --name expose-only nginx:demo
docker inspect expose-only --format '{{json .NetworkSettings.Ports}}'
```

::: details 输出类似如下

```text
{"80/tcp":null}
```

:::

使用 `-p` 可以明确指定宿主机端口：

```bash
docker run -d --name publish-one -p 8081:80 nginx:demo
docker port publish-one 80
curl http://127.0.0.1:8081
```

::: details 端口查看输出类似如下

```text
0.0.0.0:8081
```

:::

使用 `-P` 时，Docker 会把所有已声明的 `EXPOSE` 端口发布到宿主机随机高位端口：

```bash
docker run -d --name publish-all -P nginx:demo
docker port publish-all 80
```

::: details 端口查看输出类似如下

```text
0.0.0.0:32768
```

:::

清理示例容器：

```bash
docker rm -f expose-only publish-one publish-all
```

## FROM：选择基础镜像

`FROM` 决定镜像的系统环境、包管理器、默认 shell 和基础文件系统。

```dockerfile
FROM alpine:3.20
```

选型建议：

- 使用明确 tag，避免依赖 `latest` 作为生产版本。
- 优先选择官方镜像或维护活跃、来源可信的镜像。
- 在体积和兼容性之间权衡：Alpine 约 7 MB 但使用 musl libc；Debian Slim 约 80 MB 但兼容性更好。

## RUN：执行构建命令

`RUN` 在构建阶段执行命令，常用于安装依赖、创建用户、下载文件等操作。每条 `RUN` 会生成一个新的镜像层。

```dockerfile [Dockerfile]
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

Docker 按指令顺序逐层构建并使用缓存：当某一层发生变化（如源文件内容变更），该层及其后续所有层都会重新构建。因此指令顺序直接影响构建效率。

**放在前面**（变更频率低，可充分利用缓存）：

- 系统依赖安装（`apt-get install`、`apk add`）
- 基础工具和用户创建

**放在后面**（变更频率高）：

- 应用源码 `COPY`
- 频繁变化的配置文件
- 构建产物

合并多个 `RUN` 到同一层，并在同一条命令中清理缓存，避免将无用文件留进镜像：

```dockerfile
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
```

## LABEL：镜像元数据

`LABEL` 用来给镜像添加结构化元数据，例如维护者、版本、源码地址、构建时间等，便于仓库、扫描工具和平台识别。

```dockerfile [Dockerfile]
FROM alpine:3.20
LABEL maintainer="yleoer" version="demo"
LABEL multiple="true"
```

```bash
docker build -t alpine:label .
docker inspect alpine:label | grep Labels -A 20
```

推荐使用 OCI 标准标签，与 Harbor、GitHub Container Registry 等平台兼容：

```dockerfile
LABEL maintainer="platform@example.com"
LABEL org.opencontainers.image.title="demo-app"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.source="https://example.com/repo/demo-app"
LABEL org.opencontainers.image.description="Demo application image"
```

## HEALTHCHECK：容器健康检查

`HEALTHCHECK` 告诉 Docker 如何判断容器是否正常运行。没有它时 Docker 只能判断进程是否存活，无法感知应用是否已经挂起、超时或返回错误。

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1:80/ || exit 1
```

检查命令在容器内部执行，必须使用镜像内实际存在的工具：Alpine 系镜像（如 `nginx:1.27-alpine`）自带 busybox `wget`，默认没有 `curl`。检查路径也应指向应用真实提供的端点——静态站点检查 `/`，后端服务通常暴露专门的 `/healthz`。

| 参数                 | 含义                                   | 默认值 |
|--------------------|--------------------------------------|-----|
| `--interval`       | 每次检查的间隔时间                            | 30s |
| `--timeout`        | 单次检查的超时时间                            | 30s |
| `--retries`        | 连续失败多少次后判定为 unhealthy                | 3   |
| `--start-period`   | 启动初始化期时长，此期间的检查失败不计入 `--retries`     | 0s  |
| `--start-interval` | 启动初始化期内的检查间隔（Docker Engine 25.0 及以上） | 5s  |

健康状态会显示在 `docker ps` 的 `STATUS` 列：

```text
CONTAINER ID   IMAGE         STATUS                    PORTS
a1b2c3d4e5f6   app:v1.0.0    Up 10 minutes (healthy)   0.0.0.0:8080->8080/tcp
```

Kubernetes 不会自动读取 Docker 镜像中的 `HEALTHCHECK` 指令转换为 Pod 探针。部署到 Kubernetes 时，仍需在 Pod spec 中显式配置 `livenessProbe`、`readinessProbe` 或 `startupProbe`。但 `HEALTHCHECK` 在 Docker Compose 和本地 Docker 调试中仍然有效。

## 编写原则

- 固定基础镜像版本，不依赖 `latest`。
- 变更少的内容放前面，充分发挥缓存复用。
- 敏感信息（密码、Token、私钥）不通过 `ARG` 或 `ENV` 写入镜像；构建阶段使用 BuildKit secret mount（见 [BuildKit 构建挂载与 heredoc](./6-BuildKit构建挂载与heredoc.md)），运行阶段通过 Secret 或挂载文件注入。
- 一个容器只运行一个主要进程，便于管理、监控和排障。
- 按运行方式评估是否添加 `HEALTHCHECK`，并优先使用非 root 用户。
- 构建完成后用 `docker scout` 或 Harbor / Trivy 扫描已知漏洞。
- 日志一律输出到 stdout/stderr，由容器运行时统一收集。
