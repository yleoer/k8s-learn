# Dockerfile 与构建上下文

Dockerfile 是一个纯文本文件，用一组构建指令描述镜像如何生成。镜像制作的最小闭环是：准备构建上下文、编写 Dockerfile、执行 `docker build`、运行容器验证结果。

构建上下文是 Dockerfile 能访问的文件范围。`docker build` 最后的路径参数通常写为 `.`，表示把当前目录作为上下文发送给 Docker daemon；`COPY`、`ADD` 只能读取这个上下文中的文件。

## 常用指令

| 指令            | 作用                                    |
|---------------|---------------------------------------|
| `FROM`        | 指定基础镜像并创建构建阶段，通常是第一条指令；仅 `ARG` 可在其前声明 |
| `RUN`         | 在构建阶段执行命令，产生新的镜像层                     |
| `COPY`        | 复制文件或目录到镜像                            |
| `ADD`         | 复制文件到镜像，额外支持自动解压本地 tar 包和从远程 URL 获取内容 |
| `WORKDIR`     | 设置后续指令的工作目录                           |
| `USER`        | 设置当前阶段后续指令和容器运行时使用的用户                 |
| `ENV`         | 设置环境变量，构建阶段和运行阶段均可见                   |
| `ARG`         | 设置构建参数，仅在构建阶段可见                       |
| `CMD`         | 容器启动时的默认命令，可被 `docker run` 覆盖         |
| `ENTRYPOINT`  | 容器入口命令，`CMD` 的内容会作为它的默认参数             |
| `EXPOSE`      | 声明容器计划监听的端口，仅写入镜像元数据                  |
| `LABEL`       | 添加镜像元数据，例如维护者、版本、源码地址                 |
| `HEALTHCHECK` | 定义检查容器是否健康的方式                         |

> [!NOTE]
> `MAINTAINER` 已废弃，改用 `LABEL maintainer="..."`。

## 第一个镜像

从最简单的 Dockerfile 开始：复制静态文件到 nginx 镜像，并声明容器内应用计划监听的端口。

先准备一个静态文件目录，确保构建上下文中存在 `COPY` 指令要复制的源路径：

```bash
mkdir -p html
echo '<h1>Hello nginx</h1>' > html/index.html
```

```dockerfile [Dockerfile]
FROM nginx:1.31-alpine
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
[+] Building 2.1s (7/7) FINISHED
 => [internal] load build definition from Dockerfile                         0.0s
 => => transferring dockerfile: 99B                                          0.0s
 => [internal] load metadata for docker.io/library/nginx:1.31-alpine       2.0s
 => [internal] load .dockerignore                                            0.0s
 => => transferring context: 2B                                              0.0s
 => [internal] load build context                                            0.0s
 => => transferring context: 82B                                             0.0s
 => CACHED [1/2] FROM docker.io/library/nginx:1.31-alpine                  0.0s
 => [2/2] COPY ./html /usr/share/nginx/html                                  0.0s
 => exporting to image                                                       0.0s
 => => exporting layers                                                      0.0s
 => => writing image sha256:<image-id>                                       0.0s
 => => naming to docker.io/library/nginx:demo                                0.0s
```

:::

运行验证：

```bash
docker run -d --name nginx-demo -p 8080:80 nginx:demo
curl http://127.0.0.1:8080
```

::: details 输出类似如下

```text
<h1>Hello nginx</h1>
```

:::

清理示例容器：

```bash
docker rm -f nginx-demo
```

## 构建上下文

每次执行 `docker build`，Docker 会把命令指定的目录作为构建上下文发送给 daemon。Dockerfile 默认位于上下文根目录，也可以用 `-f` 指定其他路径：

```bash
docker build -f docker/Dockerfile -t nginx:demo .
```

上面命令中，Dockerfile 文件来自 `docker/Dockerfile`，但构建上下文仍然是当前目录 `.`。因此 Dockerfile 中的 `COPY ./html /usr/share/nginx/html` 仍然从当前目录下的 `html/` 读取文件。

上下文目录中的文件默认都会被打包发送。`.git`、`node_modules`、构建产物、日志等无关内容应通过 `.dockerignore` 排除，避免构建上下文过大；相关规则在 [文件复制与运行用户](./3-文件复制与运行用户.md) 中记录。
