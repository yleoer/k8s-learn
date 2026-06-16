# COPY、ADD、WORKDIR 与 USER

这四条指令控制文件如何进入镜像、命令在哪个目录执行、以及进程以什么身份运行。

## COPY 与 ADD

`COPY` 和 `ADD` 都用于把文件从构建上下文放入镜像，但语义不同：**默认用 `COPY`，只在确实需要自动解压本地 tar 包时改用 `ADD`**。

### ADD：自动解压 tar 包

`ADD` 的核心特性是：如果源文件是一个本地 tar 包，它会被自动解压到目标路径。其他场景和 `COPY` 行为一致。

先准备一个 tar 包：

```bash
mkdir -p webroot && echo '<h1>hello</h1>' > webroot/index.html
tar czf index.tar.gz -C webroot .
```

```dockerfile
FROM nginx:alpine
ADD ./index.tar.gz /usr/share/nginx/html/
```

构建运行后，`/usr/share/nginx/html/` 下将是解压后的 `index.html`，而非 `index.tar.gz` 文件。

### COPY：普通文件复制

```dockerfile
FROM nginx:alpine
COPY webroot/ /usr/share/nginx/html/
```

`COPY` 的源路径如果以 `/` 结尾，表示复制目录**里面的内容**而非目录本身。`COPY webroot/ /usr/share/nginx/html/` 把 `webroot` 下的文件放入目标路径，不包含 `webroot` 这一层目录名。

对比不加尾部斜杠：

```dockerfile
COPY webroot /usr/share/nginx/html/
# 结果: /usr/share/nginx/html/webroot/...

COPY webroot/ /usr/share/nginx/html/
# 结果: /usr/share/nginx/html/...（webroot 目录名被剥离）
```

这一点容易出错，建议统一使用尾部 `/` 并将目标写为绝对路径。

### 文件权限控制

在复制的同时设置所有者和权限，避免后续再用 `RUN chown` 或 `RUN chmod` 产生额外的镜像层：

```dockerfile
COPY --chown=nginx:nginx webroot/ /usr/share/nginx/html/
COPY --chmod=644 index.html /usr/share/nginx/html/index.html
COPY --chown=1001:1001 --chmod=755 app /usr/local/bin/app
```

### 选择建议

- 普通文件、目录和编译产物 → `COPY`。
- 本地 tar 包确实需要解压时 → `ADD`。
- 远程 URL 下载 → 用 `RUN curl` 或 `RUN wget`，并在同一层清理，不要用 `ADD <url>`（它不提供缓存控制，下载的临时文件会在镜像中留痕）。

## WORKDIR：工作目录

`WORKDIR` 设置后续指令的执行路径，影响 `RUN`、`CMD`、`ENTRYPOINT`、`COPY` 和 `ADD` 的相对路径解析。

```dockerfile
FROM nginx:alpine
WORKDIR /usr/share/nginx/html
COPY webroot/ .
```

这里 `COPY webroot/ .` 的 `.` 指当前 `WORKDIR`，即 `/usr/share/nginx/html`。

`WORKDIR` 的行为：

- 如果指定的目录不存在，Docker 会自动创建（相当于隐含了一次 `RUN mkdir -p`）。
- 可以在 Dockerfile 中多次使用，后续设置基于前一次的相对路径。
- 始终建议写绝对路径，避免因上下文切换导致的路径混乱。

## USER：运行用户

`USER` 设定容器启动后进程使用的身份。默认以 root 运行，生产环境应优先切换到非 root 用户。

```dockerfile
FROM alpine:3.20
RUN addgroup -S app && adduser -S app -G app
WORKDIR /app
COPY --chown=app:app app /app/app
USER app
CMD ["/app/app"]
```

要点：

- 先创建用户和组，再 `COPY` 文件并设置 `--chown`，最后通过 `USER` 切换运行身份。
- 用户名 `USER app` 和 UID `USER 1001` 均可，UID 在跨系统时更一致。
- 切换用户后，应用只能访问该用户有权限的路径。日志目录、临时文件目录、挂载的数据卷都要提前设置好权限。
- 如果 Dockerfile 先以 root 安装依赖，再通过 `USER` 切换身份，而安装目录仅 root 可写，运行时可能出现权限错误。此时应在安装阶段设置所有权，或将运行时数据写入当前用户有权限的路径。

## 完整示例：四条指令配合

以下 Dockerfile 把 COPY、WORKDIR、USER 组合起来，展示一个典型的可执行文件部署流程：

```dockerfile
FROM alpine:3.20

# 创建运行时用户
RUN addgroup -S app && adduser -S app -G app

# 设置工作目录
WORKDIR /app

# 复制二进制并同时设置权限
COPY --chown=app:app --chmod=755 server /app/server

# 切换用户
USER app

EXPOSE 8080
CMD ["/app/server"]
```

构建上下文中的 `server` 二进制（提前通过 Go、Rust 或 C 编译好的可执行文件）被放入 `/app/`，所有者为 `app`，权限为 `755`，进程以 `app` 身份运行。
