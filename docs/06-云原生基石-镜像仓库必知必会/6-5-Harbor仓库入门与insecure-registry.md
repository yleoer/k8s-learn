# 03-5 Harbor 仓库入门与 insecure-registry

Harbor 安装完成后，需要验证 Docker 客户端能否登录、推送和拉取镜像。如果 Harbor 没有配置 HTTPS，还需要在所有使用它的节点上配置 `insecure-registries`。

## 登录测试

```bash
docker login YOUR_HARBOR_ADDRESS
```

输入 Harbor 用户名和密码，例如：

```text
admin / Harbor12345
```

登录成功后，Docker 会把认证信息保存到当前用户的 Docker 配置中。

## 创建项目

在 Harbor Web 控制台中创建项目，例如：

```text
library
```

项目可以设置为公开或私有：

- 公开项目：未登录也可以拉取镜像。
- 私有项目：需要登录并具备权限后才能拉取或推送。

## 推送镜像到 Harbor

准备测试镜像：

```bash
docker pull nginx:alpine
```

打标签：

```bash
docker tag nginx:alpine YOUR_HARBOR_ADDRESS/library/nginx:alpine
```

推送：

```bash
docker push YOUR_HARBOR_ADDRESS/library/nginx:alpine
```

拉取验证：

```bash
docker pull YOUR_HARBOR_ADDRESS/library/nginx:alpine
```

## 配置 insecure-registries

如果 Harbor 使用 HTTP，或者使用了客户端不信任的自签证书，Docker 默认会拒绝访问。需要在所有 Kubernetes 节点的 Docker 配置中添加 `insecure-registries`。

编辑配置文件：

```bash
vim /etc/docker/daemon.json
```

添加配置：

```json
{
  "insecure-registries": ["YOUR_HARBOR_ADDRESS"]
}
```

重启 Docker：

```bash
systemctl daemon-reload
systemctl restart docker
```

再次登录测试：

```bash
docker login YOUR_HARBOR_ADDRESS
```

## 注意事项

- `YOUR_HARBOR_ADDRESS` 要和镜像地址中的仓库地址保持一致。
- 如果 Harbor 使用了端口，例如 `192.168.1.10:8080`，配置中也要带端口。
- Kubernetes 集群中每个可能拉取镜像的节点都要配置。
- 生产环境更推荐给 Harbor 配置可信 HTTPS 证书，而不是长期使用 HTTP。
- 如果节点使用的是 containerd，还需要在 containerd 中配置对应仓库的 insecure 访问。
