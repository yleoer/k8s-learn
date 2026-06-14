# ENV、CMD 与默认命令

`ENV` 用于设置环境变量，`CMD` 用于设置容器默认执行的命令。

## ENV

```dockerfile
FROM centos:7
LABEL maintainer="yleoer"
RUN useradd yleoer
RUN mkdir /yleoer
ENV envir=test version=1.0
CMD echo "envir:$envir version:$version"
```

构建：

```bash
docker build -t centos:env-cmd .
```

验证：

```bash
docker run --rm centos:env-cmd
```

输出：

```text
envir:test version:1.0
```

## CMD

`CMD` 是容器默认命令，可以被 `docker run` 后面的命令覆盖。

```dockerfile
CMD ["nginx", "-g", "daemon off;"]
```

运行时覆盖：

```bash
docker run --rm nginx:alpine nginx -v
```

## Shell 格式与 Exec 格式

Shell 格式：

```dockerfile
CMD echo "$envir:$version"
```

Exec 格式：

```dockerfile
CMD ["echo", "hello"]
```

更推荐 Exec 格式，因为信号处理更直接，也更不容易受到 shell 转义影响。如果需要环境变量展开，可以使用：

```dockerfile
CMD ["sh", "-c", "echo envir:$envir version:$version"]
```
