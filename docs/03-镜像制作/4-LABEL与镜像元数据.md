# LABEL 与镜像元数据

`LABEL` 用来给镜像添加元数据，例如维护者、版本、源码地址、构建时间等。

## 基本用法

```dockerfile
FROM centos:7
LABEL maintainer="yleoer" version="demo"
LABEL multiple="true"
```

构建：

```bash
docker build -t centos:label .
```

查看：

```bash
docker inspect centos:label | grep Labels -A 20
```

## 推荐字段

```dockerfile
LABEL maintainer="platform@example.com"
LABEL org.opencontainers.image.title="demo-app"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.source="https://example.com/repo/demo-app"
LABEL org.opencontainers.image.description="Demo application image"
```

OCI 推荐了一组标准 label，便于镜像仓库、扫描工具和平台读取元数据。

## LABEL 与 MAINTAINER

`MAINTAINER` 已经不推荐使用：

```dockerfile
MAINTAINER yleoer
```

推荐改成：

```dockerfile
LABEL maintainer="yleoer"
```
