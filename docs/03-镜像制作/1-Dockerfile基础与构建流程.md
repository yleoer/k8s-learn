# Dockerfile 基础与构建流程

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
| `CMD` | 设置容器默认命令，可被覆盖 |
| `ENTRYPOINT` | 设置容器入口命令 |
| `ARG` | 设置构建参数 |

`MAINTAINER` 已不推荐使用，建议用 `LABEL maintainer="..."` 替代。

## 构建流程

准备 Dockerfile：

```dockerfile
FROM nginx:alpine
COPY ./html /usr/share/nginx/html
EXPOSE 80
```

构建镜像：

```bash
docker build -t nginx:demo .
```

运行验证：

```bash
docker run -d --name nginx-demo -p 8080:80 nginx:demo
curl http://127.0.0.1:8080
```

## 编写原则

- 优先选择明确版本的基础镜像。
- 指令顺序要考虑缓存复用。
- 不把密码、token 等敏感信息写进镜像。
- 一个镜像只负责一个主要进程。
- 构建产物尽量小、依赖尽量少。
