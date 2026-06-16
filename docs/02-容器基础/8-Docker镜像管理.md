# Docker 镜像管理

镜像管理包括搜索、拉取、查看、打标签、删除、导出和导入。

## 搜索镜像

```bash
docker search redis
```

<details>
<summary>docker search 示例</summary>

```text
$ docker search redis
NAME                   DESCRIPTION                                      STARS     OFFICIAL
redis                  Redis is an open source key-value store that…   14000     [OK]
bitnami/redis          Bitnami Redis Docker Image                      300
redis/redis-stack      Redis Stack with JSON, Search, Timeseries…      250
```

</details>

`OFFICIAL [OK]` 表示官方镜像。生产环境优先选择维护活跃、来源可信、版本明确的镜像。

## 下载镜像

```bash
docker pull redis:8-alpine
```

## 查看本地镜像

```bash
docker images
```

<details>
<summary>docker images 示例</summary>

```text
$ docker images
REPOSITORY   TAG          IMAGE ID       CREATED       SIZE
redis        8-alpine     a1b2c3d4e5f6   2 days ago    35MB
nginx        1.27-alpine  b2c3d4e5f6g7   5 days ago    45MB
alpine       3.20         c3d4e5f6g7h8   2 weeks ago   7.4MB
```

</details>

## 更改镜像 tag

```bash
docker tag redis:latest redis:local
docker images | grep redis
```

打 tag 不会复制镜像内容，只是给同一个镜像 ID 增加一个引用。

## 删除镜像

```bash
docker rmi redis:local
docker rmi redis:latest
```

如果一个镜像还有其它 tag 引用，删除时通常只会 `Untagged`。当所有引用都删除且没有容器使用时，镜像层才会真正 `Deleted`。

## 删除 none 镜像

`<none>` 镜像通常来自构建过程中的悬空镜像。查看：

```bash
docker images -f dangling=true
```

删除悬空镜像：

```bash
docker image prune
```

不交互删除：

```bash
docker image prune -f
```

删除所有当前没有被容器使用的镜像要更谨慎：

```bash
docker image prune -a
```

## 导出和导入镜像

```bash
docker save -o nginx.alpine.tar nginx:alpine
docker load -i nginx.alpine.tar
```

`docker save/load` 保留镜像层和 tag，适合离线迁移镜像。
