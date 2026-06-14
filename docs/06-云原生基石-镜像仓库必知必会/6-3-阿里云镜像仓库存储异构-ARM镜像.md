# 03-3 阿里云镜像仓库存储异构 ARM 镜像

不同 CPU 架构需要不同的镜像构建产物。常见架构包括 `amd64` 和 `arm64`，如果 Kubernetes 集群中同时存在 x86 和 ARM 节点，就需要关注镜像架构问题。

## 查看本机架构

```bash
uname -m
```

常见结果：

| 输出 | 架构 |
| --- | --- |
| `x86_64` | `amd64` |
| `aarch64` | `arm64` |

## 单架构镜像标签

可以用标签区分不同架构：

```bash
docker build -t registry.cn-hangzhou.aliyuncs.com/YOUR_NAMESPACE/app:v1.0.0-amd64 .
docker build -t registry.cn-hangzhou.aliyuncs.com/YOUR_NAMESPACE/app:v1.0.0-arm64 .
```

推送：

```bash
docker push registry.cn-hangzhou.aliyuncs.com/YOUR_NAMESPACE/app:v1.0.0-amd64
docker push registry.cn-hangzhou.aliyuncs.com/YOUR_NAMESPACE/app:v1.0.0-arm64
```

这种方式简单直观，但部署时需要根据节点架构选择不同镜像标签。

## 多架构镜像

更推荐使用多架构镜像，让同一个镜像标签同时包含 `amd64` 和 `arm64` 产物：

```bash
docker buildx create --use
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t registry.cn-hangzhou.aliyuncs.com/YOUR_NAMESPACE/app:v1.0.0 \
  --push .
```

拉取时，容器运行时会根据节点架构自动选择匹配的镜像。

## 验证镜像架构

```bash
docker buildx imagetools inspect registry.cn-hangzhou.aliyuncs.com/YOUR_NAMESPACE/app:v1.0.0
```

重点检查输出中是否同时包含：

```text
linux/amd64
linux/arm64
```

## 注意事项

- 基础镜像必须支持目标架构。
- 二进制程序需要按目标架构编译。
- 多架构镜像通常需要直接 `--push` 到远端仓库。
- Kubernetes 混合架构集群中，镜像架构不匹配会导致 Pod 拉取成功但启动失败。
