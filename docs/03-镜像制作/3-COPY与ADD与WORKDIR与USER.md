# COPY、ADD、WORKDIR 与 USER

这四条指令控制文件如何进入镜像、在哪里执行命令、以及以什么身份运行。

## COPY 与 ADD

`ADD` 和 `COPY` 都能把文件放进镜像，但语义不同：一般优先使用 `COPY`，只有明确需要自动解压本地 tar 包时才用 `ADD`。

### ADD：带自动解压

```dockerfile
FROM nginx:alpine
ADD ./index.tar.gz /usr/share/nginx/html/
WORKDIR /usr/share/nginx/html
```

本地 tar 包会被自动解压到目标路径。

### COPY：普通文件复制

```dockerfile
FROM nginx:alpine
COPY webroot/ /usr/share/nginx/html/
```

`COPY webroot/ .` 表示复制 `webroot` 目录里的内容，不包含 `webroot` 目录本身。

### 文件权限控制

使用 `--chown` 设置所有者和组：

```dockerfile
COPY --chown=nginx:nginx webroot/ /usr/share/nginx/html/
```

使用 `--chmod` 设置权限：

```dockerfile
COPY --chmod=644 index.html /usr/share/nginx/html/index.html
```

组合使用：

```dockerfile
COPY --chown=1001:1001 --chmod=755 app /usr/local/bin/app
```

### 选择建议

- 普通文件复制优先用 `COPY`。
- 本地 tar 包确实需要自动解压时用 `ADD`。
- 生产 Dockerfile 更推荐显式、可读、可审查的方式。

## WORKDIR：工作目录

```dockerfile
FROM nginx:alpine
WORKDIR /usr/share/nginx/html
COPY webroot/ .
```

`WORKDIR` 的作用：

- 后续 `RUN`、`CMD`、`ENTRYPOINT`、`COPY`、`ADD` 的相对路径基准。
- 如果目录不存在，会自动创建。
- 可以多次设置，后续相对路径基于当前工作目录。

建议使用绝对路径，避免路径理解混乱。

## USER：运行用户

```dockerfile
FROM alpine:3.20
RUN addgroup -S app && adduser -S app -G app
WORKDIR /app
COPY --chown=app:app app /app/app
USER app
CMD ["/app/app"]
```

`USER` 的作用：

- 设置构建后续阶段或容器运行时使用的用户。
- 降低容器进程以 root 身份运行带来的风险。

可以使用用户名 `USER app`，也可以使用 UID `USER 1001`。

使用非 root 用户时，要确保应用需要读写的目录有正确权限。配合 `COPY --chown` 可以在复制文件的同时赋予正确的所有者。
