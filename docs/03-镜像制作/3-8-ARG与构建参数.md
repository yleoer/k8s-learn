# ARG 与构建参数

`ARG` 用于定义构建时参数。它可以在 `docker build` 过程中传入，但默认不会成为容器运行时环境变量。

## 基本用法

```dockerfile
FROM centos:7
ARG USERNAME
ARG DIR="defaultValue"

RUN useradd -m "$USERNAME" -u 1001 && mkdir "$DIR"
```

构建：

```bash
docker build --build-arg USERNAME="test_arg" -t test:arg .
```

## ARG 与 ENV 的区别

| 对比项 | ARG | ENV |
| --- | --- | --- |
| 生效阶段 | 构建阶段 | 构建阶段和运行阶段 |
| 运行容器可见 | 默认不可见 | 可见 |
| 适合用途 | 构建版本、下载地址、开关 | 应用运行配置 |

示例：

```dockerfile
ARG APP_VERSION=1.0.0
ENV APP_ENV=prod
```

## 不要传敏感信息

不要用 `ARG` 传密码、token、私钥等敏感信息。构建历史和缓存中可能留下痕迹。

## ARG 用于基础镜像版本

```dockerfile
ARG ALPINE_VERSION=3.20
FROM alpine:${ALPINE_VERSION}
```

构建：

```bash
docker build --build-arg ALPINE_VERSION=3.21 -t demo:alpine321 .
```
