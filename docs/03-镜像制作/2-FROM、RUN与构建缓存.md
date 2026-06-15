# FROM、RUN 与构建缓存

`FROM` 指定基础镜像，`RUN` 在构建阶段执行命令。理解这两个指令和构建缓存，是写好 Dockerfile 的基础。

## FROM

```dockerfile
FROM centos:7
```

`FROM` 必须是 Dockerfile 的第一条有效构建指令。它决定镜像的系统环境、包管理器、默认 shell 和基础文件系统。

建议：

- 使用明确 tag，避免依赖 `latest`。
- 优先选择官方镜像或可信镜像。
- 生产镜像尽量选择体积小、维护活跃的基础镜像。

## RUN

创建用户示例：

```dockerfile
FROM centos:7
LABEL maintainer="yleoer"
RUN useradd yleoer
```

构建：

```bash
docker build -t centos:user .
```

验证：

```bash
docker run -it --rm centos:user cat /etc/passwd
```

## 构建缓存

Docker 构建时会按指令顺序使用缓存。某一层发生变化后，后续层缓存通常都会失效。

适合放前面的内容：

- 变化少的系统依赖安装
- 基础工具安装
- 用户创建

适合放后面的内容：

- 应用代码
- 频繁变化的配置
- 构建产物

## 合并 RUN

多个 `RUN` 会产生更多层。安装软件时通常合并命令并清理缓存：

```dockerfile
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
```
