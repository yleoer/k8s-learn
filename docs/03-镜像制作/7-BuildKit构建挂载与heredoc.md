# BuildKit 构建挂载与 heredoc

[镜像分层与构建缓存](./5-镜像分层与构建缓存.md) 和 [多阶段构建与体积优化](./6-多阶段构建与体积优化.md) 主要围绕镜像层展开：调整指令顺序、合并清理、多阶段构建。BuildKit 还提供另一类能力——`RUN --mount` 在单条指令执行期间挂载临时资源，包管理器缓存和构建密钥都不必进入镜像层；heredoc 则让多行脚本和内联文件在 Dockerfile 中保持可读。

## BuildKit 与 syntax 指令

BuildKit 是 Docker 的构建引擎，Docker Engine 23.0 起在 Linux 上作为默认构建器，`docker build` 等价于 `docker buildx build`；构建 Windows 容器镜像时仍使用旧构建器。

Dockerfile 语法由 frontend 镜像决定，通过文件第一行的解析器指令声明：

```dockerfile
# syntax=docker/dockerfile:1
```

`docker/dockerfile:1` 表示跟随 1.x 最新稳定语法，每次构建时自动检查更新。本文使用的特性对语法版本有最低要求：`RUN --mount` 需要 1.2 以上，heredoc 需要 1.4 以上，secret 的 `env` 参数需要 1.10 以上；声明 `docker/dockerfile:1` 即可全部覆盖。

> [!NOTE]
> `# syntax` 指令必须位于 Dockerfile 最顶部，之前不能有任何注释、空行或指令，否则会被当作普通注释忽略。

## RUN --mount 总览

`--mount` 为单条 `RUN` 指令附加挂载，挂载内容只在该指令执行期间可见，不会写入镜像层：

| 类型       | 作用                   | 典型场景                       |
|----------|----------------------|----------------------------|
| `bind`   | 挂载构建上下文或其他阶段的目录，默认只读 | 读取 `go.mod` 等文件而不产生 COPY 层 |
| `cache`  | 挂载跨构建复用的缓存目录         | apt、pip、npm、Go 模块缓存        |
| `tmpfs`  | 挂载内存文件系统             | 临时中间文件                     |
| `secret` | 挂载密钥文件或环境变量          | 私有仓库凭据、API Token           |
| `ssh`    | 转发 SSH agent         | 拉取私有 Git 仓库                |

## 缓存挂载

`RUN --mount=type=cache` 把一个持久化缓存目录挂载进构建容器。缓存内容在多次构建之间保留，且不影响指令缓存的判定：源码变化导致 `RUN` 重新执行时，包管理器仍能命中之前下载的内容。

常用参数如下：

| 参数            | 默认值        | 说明                                    |
|---------------|------------|---------------------------------------|
| `target`      | 必填         | 缓存在构建容器内的挂载路径                         |
| `id`          | 同 `target` | 缓存标识，不同用途的同路径缓存应显式区分                  |
| `sharing`     | `shared`   | 并发共享模式，可选 `shared`、`private`、`locked` |
| `from`        | 空目录        | 以某个构建阶段作为缓存初始内容                       |
| `mode`        | `0755`     | 缓存目录权限                                |
| `uid` / `gid` | `0`        | 缓存目录属主                                |

Go 项目结合多阶段构建的写法：

```dockerfile [Dockerfile]
# syntax=docker/dockerfile:1
FROM golang:1.23-alpine AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download
COPY . .
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -ldflags="-s -w" -o /app/server .

FROM alpine:3.20
RUN apk add --no-cache ca-certificates
WORKDIR /app
COPY --from=builder /app/server /app/server
CMD ["/app/server"]
```

`/go/pkg/mod` 缓存模块下载，`/root/.cache/go-build` 缓存编译产物。`go.mod` 未变化时 `go mod download` 直接命中层缓存；源码变化触发重新编译时，增量编译仍可复用 build cache，重复构建速度明显快于每次全量下载和编译。

apt 需要额外处理：Debian、Ubuntu 官方镜像内置的 `docker-clean` 配置会在安装后删除已下载的包，需要先关闭它，缓存挂载才有内容可留：

```dockerfile [Dockerfile]
# syntax=docker/dockerfile:1
FROM ubuntu:24.04
RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends gcc
```

apt 要求独占其数据目录，因此使用 `sharing=locked`：并发构建会依次等待锁，而默认的 `shared` 允许同时读写，`private` 则为每个并发构建生成独立副本。使用缓存挂载后，`rm -rf /var/lib/apt/lists/*` 这类清理动作不再必要——列表和包缓存本身就不在镜像层里。

pip 和 npm 的写法类似：

```dockerfile
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt

RUN --mount=type=cache,target=/root/.npm \
    npm install
```

缓存挂载的边界需要理解清楚：

- 缓存属于当前构建器（BuildKit 实例）本地，切换构建器后缓存不共享，`--cache-to` 导出的层缓存也不包含缓存挂载内容。
- 缓存可能在任何时候被垃圾回收，其他构建也可能覆写其中的文件。构建逻辑不能依赖缓存内容存在，缓存只应作为加速手段。
- CI 环境每次新建构建器时缓存挂载默认为空，收益主要体现在常驻构建器或本地开发场景。

清理构建缓存时，缓存挂载对应的记录类型为 `exec.cachemount`：

```bash
docker buildx du
docker buildx prune --filter "type=exec.cachemount"
```

## secret 挂载

构建阶段经常需要私有仓库凭据或 API Token。`ARG` 和 `ENV` 都不适合传递这类信息：`ENV` 会永久写入镜像配置；`ARG` 虽然不进入最终镜像文件系统，但会保留在 `docker history` 的构建历史和 provenance 记录中。`RUN --mount=type=secret` 让密钥只在单条指令执行期间可见，不进入镜像层，也不进入构建缓存。

常用参数如下：

| 参数         | 默认值                 | 说明                                     |
|------------|---------------------|----------------------------------------|
| `id`       | `target` 路径的文件名     | 密钥标识，与构建命令中的 `--secret id=` 对应         |
| `target`   | `/run/secrets/<id>` | 挂载为文件时的路径；`target` 与 `env` 都未设置时使用默认路径 |
| `env`      | 未启用                 | 挂载为环境变量，可与 `target` 同时使用               |
| `required` | `false`             | 为 `true` 时未提供该密钥直接报错                   |
| `mode`     | `0400`              | 密钥文件权限                                 |

以文件形式挂载 pip 私有源配置：

```dockerfile [Dockerfile]
# syntax=docker/dockerfile:1
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt ./
RUN --mount=type=secret,id=pipconf,target=/etc/pip.conf \
    --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt
COPY . .
CMD ["python", "main.py"]
```

构建时通过 `--secret` 提供来源文件：

```bash
docker build --secret id=pipconf,src=$HOME/.config/pip/pip.conf -t app:v1.0.0 .
```

以环境变量形式挂载 Token：

```dockerfile
RUN --mount=type=secret,id=API_TOKEN,env=API_TOKEN \
    curl -fsS -H "Authorization: Bearer $API_TOKEN" https://api.example.com/resource -o /tmp/resource.json
```

```bash
export API_TOKEN=<token>
docker build --secret id=API_TOKEN .
```

`--secret id=API_TOKEN` 省略 `src` 和 `env` 时，自动读取宿主机上同名环境变量。构建完成后可以用 `docker history <image>` 确认构建历史中没有密钥内容。

> [!CAUTION]
> secret 挂载只保证密钥不落入镜像层。如果 `RUN` 命令把密钥写入镜像内文件，或在日志中回显密钥内容，泄漏渠道依然存在。

## 其他挂载类型

`bind` 是 `--mount` 的默认类型，把构建上下文或指定阶段的目录挂载进来，默认只读；加 `rw` 后可写，但写入内容在 `RUN` 结束后丢弃，不会进入镜像层：

```dockerfile
RUN --mount=type=bind,source=go.sum,target=go.sum \
    --mount=type=bind,source=go.mod,target=go.mod \
    go mod download -x
```

`tmpfs` 提供内存文件系统，适合确定不需要保留的中间文件。`ssh` 把宿主机的 SSH agent 转发进构建容器，用于拉取私有 Git 仓库：

```dockerfile
RUN --mount=type=ssh \
    git clone git@github.com:<org>/<private-repo>.git /src
```

```bash
docker build --ssh default .
```

## heredoc 写法

heredoc 让多行内容直接内联在 Dockerfile 中，替代冗长的 `&&` 链和反斜杠续行：

```dockerfile [Dockerfile]
# syntax=docker/dockerfile:1
FROM ubuntu:24.04
RUN <<EOT
set -eux
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl
rm -rf /var/lib/apt/lists/*
EOT
```

整个 heredoc 块作为一个脚本交给默认 shell 执行，只产生一个镜像层。

> [!WARNING]
> heredoc 块默认由 `/bin/sh -c` 执行，中间某条命令失败不会中断脚本，`RUN` 的退出码只取决于最后一条命令。这与 `&&` 链的短路行为不同，脚本开头必须显式 `set -e`（或 `set -eux`），否则中间步骤的失败会被静默吞掉。官方文档示例也统一以 `set -ex` 开头。

heredoc 可以指定解释器。分隔符后写命令，或在块内第一行写 shebang：

```dockerfile
RUN <<EOT bash
set -euxo pipefail
apt-get update
apt-get install -y vim
EOT

RUN <<EOT
#!/usr/bin/env python3
print("hello world")
EOT
```

带 shebang 的 heredoc 会被写成可执行文件后运行，解释器行必须是块内第一行且不能缩进。

`COPY` 配合 heredoc 可以直接生成镜像内文件：

```dockerfile [Dockerfile]
# syntax=docker/dockerfile:1
FROM nginx:1.27-alpine
COPY <<'EOF' /usr/share/nginx/html/index.html
<h1>hello heredoc</h1>
EOF
```

分隔符是否加引号决定变量展开时机：`<<EOF` 会在构建时展开 `$VAR`；`<<'EOF'`（或 `<<"EOF"`）按字面写入，`$VAR` 保留到运行时再由应用或 shell 处理。写入启动脚本、配置模板时通常需要加引号，避免构建时误展开。`<<-EOF` 变体会去除每行行首的 Tab，便于在 Dockerfile 中缩进对齐。

## 记录要点

- Dockerfile 第一行固定写 `# syntax=docker/dockerfile:1`，保证挂载与 heredoc 语法可用。
- 包管理器缓存用 `cache` 挂载，密钥用 `secret` 挂载，两者都不进入镜像层；`ARG`、`ENV` 不承载敏感信息。
- 同一路径服务于不同用途时显式设置缓存 `id`；apt 场景使用 `sharing=locked`。
- 构建不能依赖缓存挂载的内容存在；CI 一次性构建器中缓存挂载默认为空。
- heredoc 脚本第一行写 `set -eux`；写入文件时按需给分隔符加引号控制变量展开。
- 构建后用 `docker history` 复查，确认历史记录中没有密钥和多余体积。

## 参考

- [Dockerfile reference: RUN --mount](https://docs.docker.com/reference/dockerfile/#run---mount)
- [Dockerfile reference: Here-documents](https://docs.docker.com/reference/dockerfile/#here-documents)
- [Build secrets](https://docs.docker.com/build/building/secrets/)
- [Optimize cache usage in builds](https://docs.docker.com/build/cache/optimize/)
- [BuildKit](https://docs.docker.com/build/buildkit/)
- [Introduction to heredocs in Dockerfiles](https://www.docker.com/blog/introduction-to-heredocs-in-dockerfiles/)
