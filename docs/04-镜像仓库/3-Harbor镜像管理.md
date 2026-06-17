# Harbor 镜像管理

Harbor 安装完成后，需要验证从客户端推送镜像、从其他节点拉取镜像的完整链路。若 Harbor 使用 HTTP 或未被系统信任的证书，还需要分别配置 Docker 与 containerd 的仓库访问规则。

## 登录测试

```bash
docker login harbor.example.com
```

输入具备项目权限的用户名和密码。登录成功后，Docker 会将认证信息写入 `~/.docker/config.json`，后续执行 `docker push` 和 `docker pull` 时会自动携带凭据。

## 创建项目

在 Harbor Web 控制台进入 **项目 → 新建项目**，创建一个名为 `base` 的项目。

| 类型 | 说明 | 适用场景 |
| --- | --- | --- |
| 公开项目 | 未登录用户可以拉取镜像，但推送仍需权限 | 基础镜像、公共组件、开源镜像缓存 |
| 私有项目 | 用户必须登录并具备项目权限才能拉取 | 业务镜像、内部中间件、生产镜像 |

基础镜像可放入公开的 `base` 项目，业务镜像通常放入私有项目，并通过用户、Robot 账号或 Kubernetes Secret 控制访问。

## 推送镜像到 Harbor

```bash
# 拉取一个测试镜像
docker pull nginx:alpine

# 打标签，指向 Harbor 中的 base 项目
docker tag nginx:alpine harbor.example.com/base/nginx:alpine

# 推送镜像
docker push harbor.example.com/base/nginx:alpine
```

推送完成后，可在 Harbor 控制台进入 `base` 项目查看 `nginx` 仓库和 `alpine` 标签。若推送失败，应检查项目是否存在、账号是否具备开发人员及以上权限，以及客户端是否信任 Harbor 地址。

## 拉取验证

在另一台节点上验证拉取链路：

```bash
docker login harbor.example.com
docker pull harbor.example.com/base/nginx:alpine
```

公开项目可以省略 `docker login` 执行拉取；私有项目必须登录，或由运行时通过预置凭据完成认证。

## 配置 Docker 访问

生产环境推荐使用受信任的 HTTPS 证书。若 Harbor 使用 HTTP，可以在 Docker 中配置 `insecure-registries`：

```json
{
  "insecure-registries": ["harbor.example.com"]
}
```

带非标准端口时必须写出端口：

```json
{
  "insecure-registries": ["harbor.example.com:8080"]
}
```

修改后重启 Docker：

```bash
systemctl daemon-reload
systemctl restart docker
docker login harbor.example.com
```

若 Harbor 使用内部 CA 或自签 CA，更推荐把 CA 证书安装到 Docker 信任目录，而不是关闭校验：

```bash
mkdir -p /etc/docker/certs.d/harbor.example.com
cp ca.crt /etc/docker/certs.d/harbor.example.com/ca.crt
systemctl restart docker
```

## 配置 containerd 访问

Kubernetes 节点使用 containerd 时，Docker 的配置不会自动生效，需要单独配置 `/etc/containerd/certs.d/` 下的 `hosts.toml`。

### HTTP 仓库

```bash
sudo mkdir -p /etc/containerd/certs.d/harbor.example.com

sudo tee /etc/containerd/certs.d/harbor.example.com/hosts.toml >/dev/null <<'EOF'
server = "http://harbor.example.com"

[host."http://harbor.example.com"]
  capabilities = ["pull", "resolve", "push"]
EOF

sudo systemctl restart containerd
```

### 自签或内部 CA 证书

更稳妥的方式是分发 CA 证书并显式配置 `ca`：

```bash
sudo mkdir -p /etc/containerd/certs.d/harbor.example.com
sudo cp ca.crt /etc/containerd/certs.d/harbor.example.com/ca.crt

sudo tee /etc/containerd/certs.d/harbor.example.com/hosts.toml >/dev/null <<'EOF'
server = "https://harbor.example.com"

[host."https://harbor.example.com"]
  capabilities = ["pull", "resolve", "push"]
  ca = "/etc/containerd/certs.d/harbor.example.com/ca.crt"
EOF

sudo systemctl restart containerd
```

临时测试也可以使用 `skip_verify = true` 跳过证书校验，但不建议在生产环境长期使用。

验证 containerd 能否拉取镜像：

```bash
sudo crictl pull harbor.example.com/base/nginx:alpine
sudo crictl images | grep harbor
```

## HTTPS 权威证书场景

如果 Harbor 使用权威 CA 签发的 HTTPS 证书，且节点系统信任该 CA，Docker 和 containerd 通常不需要额外配置。客户端会通过系统证书池完成校验，这也是生产环境优先采用受信任 HTTPS 的主要原因。

## 镜像标签策略

标签不仅区分版本，也影响回滚、审计和排障效率。常见策略如下：

| 策略 | 示例 | 适用场景 |
| --- | --- | --- |
| 语义版本 | `v1.0.0`、`v2.3.1` | 正式发布 |
| Git commit | `abc1234`、`9f3c2a1` | 开发环境快速验证 |
| 构建序号 | `20260617-001` | CI/CD 自动构建 |
| 环境加版本 | `prod-v1.0.0` | 多环境版本区分 |

生产发布应避免仅使用 `latest` 标签。`latest` 只是普通标签，不一定代表最新构建，也无法稳定定位到某一次发布内容。
