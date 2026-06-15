# ARM 与多架构镜像制作

在 x86 机器上构建 ARM 镜像，或同时构建 amd64、arm64 多架构镜像，通常使用 Docker Buildx。

## 查看构建器

```bash
docker buildx ls
```

## 创建新构建器

```bash
docker buildx create \
  --name mybuilder \
  --use \
  --platform linux/amd64,linux/arm64 \
  --driver docker-container
```

初始化构建器：

```bash
docker buildx inspect --bootstrap
```

## 安装多架构模拟支持

```bash
docker run --privileged --rm tonistiigi/binfmt --install all
```

## 构建并上传 ARM 镜像

```bash
docker buildx build \
  --platform linux/arm64 \
  -t registry.example.com/demo/nginx:v2 \
  --push \
  -f ./Dockerfile .
```

## 只构建并加载到本地

```bash
docker buildx build \
  --platform linux/arm64/v8 \
  -t nginx:armv2 \
  -f ./Dockerfile . \
  --load
```

## 注意事项

- 基础镜像也必须支持对应架构。
- 如果向镜像中拷贝二进制文件，二进制文件也必须匹配目标架构。
- `--load` 通常只适合单架构镜像。
- 多架构镜像通常需要 `--push` 到镜像仓库。
