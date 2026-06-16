# CMD、ENTRYPOINT、ENV 与 ARG

这四条指令共同决定了容器的启动行为和参数传递方式。

## ENV：环境变量

`ENV` 设置运行时环境变量，在构建阶段和容器运行阶段都可见。

```dockerfile
FROM alpine:3.20
LABEL maintainer="yleoer"
RUN adduser -D yleoer
RUN mkdir /yleoer
ENV envir=test version=1.0
CMD echo "envir:$envir version:$version"
```

```bash
docker build -t alpine:env-cmd .
docker run --rm alpine:env-cmd
```

```text
envir:test version:1.0
```

## CMD：默认命令

`CMD` 是容器默认命令，可以被 `docker run` 后面的命令覆盖。

```dockerfile
CMD ["nginx", "-g", "daemon off;"]
```

运行时覆盖：

```bash
docker run --rm nginx:alpine nginx -v
```

### Shell 格式与 Exec 格式

Shell 格式（通过 shell 执行，支持变量展开）：

```dockerfile
CMD echo "$envir:$version"
```

Exec 格式（直接执行，信号处理更直接）：

```dockerfile
CMD ["echo", "hello"]
```

需要变量展开时，显式调用 shell：

```dockerfile
CMD ["sh", "-c", "echo envir:$envir version:$version"]
```

生产环境更推荐 Exec 格式，因为信号处理更直接，也不容易受 shell 转义影响。

## ENTRYPOINT：容器入口

`ENTRYPOINT` 表示容器入口命令，适合固定主程序。`CMD` 的内容会作为它的默认参数。

```dockerfile
FROM alpine:3.20
ENTRYPOINT ["echo"]
CMD ["hello"]
```

```bash
docker run --rm demo           # 输出 hello
docker run --rm demo world     # 输出 world（world 替换了 CMD）
docker run --rm --entrypoint sh demo   # 覆盖 ENTRYPOINT，进入 shell
```

## CMD 与 ENTRYPOINT 的配合

| 组合 | 效果 |
| --- | --- |
| 只用 `CMD` | 默认命令，`docker run` 后面跟命令可覆盖 |
| 只用 `ENTRYPOINT` | 固定入口，`docker run` 后面参数追加到 ENTRYPOINT 之后 |
| `ENTRYPOINT` + `CMD` | ENTRYPOINT 固定主程序，CMD 提供默认参数，运行时可替换参数 |

选择建议：

- 只需要默认命令：用 `CMD`。
- 主程序固定、参数可变：用 `ENTRYPOINT` + `CMD`。
- 复杂启动逻辑放到入口脚本，不要把一长串 shell 都塞进 Dockerfile。

## ARG：构建参数

`ARG` 用于定义构建时参数。它可以在 `docker build` 过程中传入，但默认不会成为容器运行时环境变量。

```dockerfile
FROM alpine:3.20
ARG USERNAME
ARG DIR="defaultValue"

RUN adduser -D -u 1001 "$USERNAME" && mkdir "$DIR"
```

```bash
docker build --build-arg USERNAME="test_arg" -t test:arg .
```

### ARG 与 ENV 的区别

| 对比项 | ARG | ENV |
| --- | --- | --- |
| 生效阶段 | 构建阶段 | 构建阶段和运行阶段 |
| 运行容器可见 | 默认不可见 | 可见 |
| 适合用途 | 构建版本、下载地址、开关 | 应用运行配置 |

```dockerfile
ARG APP_VERSION=1.0.0
ENV APP_ENV=prod
```

### ARG 用于基础镜像版本

```dockerfile
ARG ALPINE_VERSION=3.20
FROM alpine:${ALPINE_VERSION}
```

```bash
docker build --build-arg ALPINE_VERSION=3.21 -t demo:alpine321 .
```

> 不要用 `ARG` 传密码、token、私钥等敏感信息。构建历史和缓存中可能留下痕迹。
