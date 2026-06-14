# WORKDIR 与 USER

`WORKDIR` 设置工作目录，`USER` 设置容器运行用户。它们直接影响命令执行路径和容器安全边界。

## WORKDIR

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

## USER

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

可以使用用户名：

```dockerfile
USER app
```

也可以使用 UID：

```dockerfile
USER 1001
```

使用非 root 用户时，要确保应用需要读写的目录有正确权限。
