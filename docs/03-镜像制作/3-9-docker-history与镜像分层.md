# docker history 与镜像分层

镜像是一层一层叠加出来的。理解镜像分层，有助于优化构建速度和镜像大小。

## 查看构建历史

```bash
docker history nginx:latest
```

输出中可以看到：

- 每层对应的构建指令
- 每层大小
- `CMD`、`ENV`、`LABEL` 等元数据层
- `RUN`、`COPY`、`ADD` 等可能增加文件内容的层

## 镜像层特点

- 镜像层是只读的。
- 多个镜像可以共享相同基础层。
- 容器启动后会在镜像层上添加一个可写层。
- 删除 tag 不一定删除层，只有没有引用时才会真正删除。

## 为什么关注分层

如果 Dockerfile 这样写：

```dockerfile
RUN apt-get update
RUN apt-get install -y curl
RUN rm -rf /var/lib/apt/lists/*
```

清理命令在后面的层中执行，前面层中的缓存可能仍然占用空间。更好的方式：

```dockerfile
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
```

## 缓存优化

Docker 按指令顺序判断缓存。一旦某一层变化，后续层通常都要重新构建。

Node.js 示例：

```dockerfile
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
```
