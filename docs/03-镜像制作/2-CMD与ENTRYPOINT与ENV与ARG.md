# CMD、ENTRYPOINT、ENV 与 ARG

这四条指令共同决定容器的启动行为和参数传递方式：ENV 和 ARG 负责变量注入，CMD 和 ENTRYPOINT 负责启动命令。

## ENV：环境变量

`ENV` 设置的环境变量在构建阶段和容器运行阶段均可见，适合注入应用运行所需的配置。

```dockerfile
FROM alpine:3.20
ENV APP_ENV=production \
    APP_PORT=8080
CMD echo "env=$APP_ENV port=$APP_PORT"
```

```bash
docker build -t demo:env .
docker run --rm demo:env
```

```text
env=production port=8080
```

启动容器时可通过 `-e` 覆盖：

```bash
docker run --rm -e APP_ENV=staging demo:env
env=staging port=8080
```

多变量建议用多行写法，可读性更好：

```dockerfile
ENV APP_ENV=production \
    APP_PORT=8080 \
    APP_VERSION=1.0.0
```

## CMD：默认命令

`CMD` 定义容器启动时执行的默认命令。如果 `docker run` 后面跟了命令，`CMD` 将被覆盖。

```dockerfile
FROM alpine:3.20
CMD ["echo", "hello from cmd"]
```

```bash
docker build -t demo:cmd .
```

正常运行：

```bash
docker run --rm demo:cmd # 输出 hello from cmd

```

运行时覆盖：

```bash
docker run --rm demo:cmd echo overridden # 输出 overridden
```

### Shell 格式与 Exec 格式

Shell 格式（通过 `/bin/sh -c` 执行，支持变量展开和管道）：

```dockerfile
CMD echo "home is $HOME"
```

Exec 格式（直接调用可执行文件，不经过 shell，信号传递更可靠）：

```dockerfile
CMD ["echo", "hello"]
```

在 Exec 格式下，`$HOME` 不会被展开，因为不经过 shell。如果需要变量，显式调用 shell：

```dockerfile
CMD ["sh", "-c", "echo app version: $APP_VERSION"]
```

生产环境优先使用 Exec 格式——它直接以 PID 1 运行目标程序，能正确接收 `SIGTERM` 等信号，`docker stop` 可在超时内完成优雅退出。Shell 格式以 `/bin/sh` 作为 PID 1，目标程序只是它的子进程，信号不一定能转发到位。

## ENTRYPOINT：容器入口

`ENTRYPOINT` 定义容器入口，比 `CMD` 更难被覆盖——`docker run` 后的参数会追加到 `ENTRYPOINT` 之后，而不是替换它。适合固定主程序的场景。

```dockerfile
FROM alpine:3.20
ENTRYPOINT ["echo"]
CMD ["hello"]
```

```bash
docker build -t demo:entry .
```

```bash
docker run --rm demo:entry           # 输出 hello
docker run --rm demo:entry world     # 输出 world（world 替换了 CMD 的值）
docker run --rm demo:entry a b c     # 输出 a b c（所有参数依次追加）
```

要彻底替换 `ENTRYPOINT`，需要使用 `--entrypoint` 参数：

```bash
docker run --rm --entrypoint sh demo:entry
```

## CMD 与 ENTRYPOINT 的配合

| 组合                 | 效果                                   | 典型场景                 |
| -------------------- | -------------------------------------- | ------------------------ |
| 只用 `CMD`           | 默认命令，`docker run <args>` 直接覆盖 | 通用工具镜像、一次性任务 |
| 只用 `ENTRYPOINT`    | 固定入口，`docker run <args>` 追加参数 | 简化 CLI 调用            |
| `ENTRYPOINT` + `CMD` | 固定主程序 + 可替换的默认参数          | **最常见的生产写法**     |

常见模式的对比：

```dockerfile
# 方式一：只用 CMD（灵活，可被覆盖）
FROM nginx:alpine
CMD ["nginx", "-g", "daemon off;"]

# 方式二：ENTRYPOINT + CMD（固定入口，参数可替换）
FROM nginx:alpine
ENTRYPOINT ["nginx"]
CMD ["-g", "daemon off;"]
```

方式二的效果是 `docker run --rm nginx:prod -T` 会在 `nginx` 之后拼接 `-T`，而不是替换整个命令。

> 复杂启动逻辑（环境检查、配置模板渲染、权限修正）建议放到独立的入口脚本（如 `entrypoint.sh`），不要全部塞进 Dockerfile 指令中。

## ARG：构建参数

`ARG` 只在构建阶段可见，容器运行时默认不可用。适合控制镜像版本、下载地址、编译开关等。

```dockerfile
FROM alpine:3.20
ARG APP_USER=appuser
ARG APP_UID=1001

RUN adduser -D -u "$APP_UID" "$APP_USER"
```

```bash
docker build --build-arg APP_USER=myapp --build-arg APP_UID=2000 -t demo:arg .
```

ARG 也可用于控制基础镜像版本：

```dockerfile
ARG ALPINE_VERSION=3.20
FROM alpine:${ALPINE_VERSION}
```

```bash
docker build --build-arg ALPINE_VERSION=3.21 -t demo:alpine321 .
```

### ARG 与 ENV 的区别

| 对比项            | ARG                        | ENV                                    |
| ----------------- | -------------------------- | -------------------------------------- |
| 可见阶段          | 仅构建阶段                 | 构建阶段和运行阶段                     |
| 容器内 `env` 可见 | 默认不可见                 | 可见                                   |
| 适合用途          | 版本号、下载地址、编译开关 | 应用运行配置（端口、环境名、日志级别） |
| 运行时覆盖        | 不可覆盖                   | `docker run -e` 可覆盖                 |

实践中两者常配合使用：ARG 接收构建时的版本号，然后赋值给 ENV 供运行时读取：

```dockerfile
ARG VERSION=1.0.0
ENV APP_VERSION=$VERSION
```

> 不要用 `ARG` 传密码、Token、私钥——这些值会留在构建历史和中间层缓存中。敏感信息应在运行时通过 `docker run -e`、Kubernetes Secret 或挂载文件注入。
