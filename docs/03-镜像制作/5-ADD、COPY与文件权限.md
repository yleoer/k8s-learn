# ADD、COPY 与文件权限

`ADD` 和 `COPY` 都能把文件放进镜像，但语义不同。一般优先使用 `COPY`，只有明确需要自动解压本地 tar 包或远程 URL 能力时再考虑 `ADD`。

## ADD

使用 `ADD` 添加本地压缩包，会自动解压：

```dockerfile
FROM nginx:alpine
ADD ./index.tar.gz /usr/share/nginx/html/
WORKDIR /usr/share/nginx/html
```

## COPY

拷贝目录下内容到容器：

```dockerfile
FROM nginx:alpine
COPY webroot/ /usr/share/nginx/html/
```

`COPY webroot/ .` 表示复制 `webroot` 目录里的内容，不包含 `webroot` 目录本身。

## 文件权限

使用 `--chown` 设置所有者和组：

```dockerfile
COPY --chown=nginx:nginx webroot/ /usr/share/nginx/html/
```

使用 `--chmod` 设置权限：

```dockerfile
COPY --chmod=644 index.html /usr/share/nginx/html/index.html
```

也可以组合使用：

```dockerfile
COPY --chown=1001:1001 --chmod=755 app /usr/local/bin/app
```

## 选择建议

- 普通文件复制优先用 `COPY`。
- 本地 tar 包确实需要自动解压时用 `ADD`。
- 生产 Dockerfile 更推荐显式、可读、可审查的方式。
