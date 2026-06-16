# Harbor 镜像管理

Harbor 安装完成后，需要验证 Docker 客户端能否登录、推送和拉取镜像。如果 Harbor 使用 HTTP，或测试环境临时跳过自签证书校验，才需要配置 insecure registry。生产环境更推荐使用可信证书，或把自签 CA 分发到所有客户端节点。

## 登录测试

```bash
docker login harbor.example.com
```

输入用户名和密码（默认 `admin / Harbor12345`）。

登录成功后，认证信息保存在 `~/.docker/config.json` 中。

## 创建项目

在 Harbor Web 控制台创建项目，例如 `base`：

- **公开项目**：未登录也可以拉取。
- **私有项目**：需要登录且具备权限才能拉取或推送。

## 推送镜像到 Harbor

```bash
docker pull nginx:alpine
docker tag nginx:alpine harbor.example.com/base/nginx:alpine
docker push harbor.example.com/base/nginx:alpine
```

## 拉取验证

```bash
docker rmi harbor.example.com/base/nginx:alpine
docker pull harbor.example.com/base/nginx:alpine
```

## 配置客户端信任

客户端信任方式取决于 Harbor 的访问协议：

| Harbor 访问方式 | Docker / containerd 推荐配置 |
| --- | --- |
| 权威 CA HTTPS | 通常不需要额外配置 |
| 自签 CA HTTPS | 分发 CA 证书到客户端信任目录 |
| HTTP 测试仓库 | 配置 insecure registry |

不要把 HTTP 或跳过证书校验作为生产默认方案。它会降低镜像传输和认证过程的安全性。

## Docker 配置

### HTTP 或临时 insecure

编辑 `/etc/docker/daemon.json`：

```json
{
  "insecure-registries": ["harbor.example.com"]
}
```

如果 Harbor 使用非标准端口：

```json
{
  "insecure-registries": ["harbor.example.com:8080"]
}
```

重启 Docker：

```bash
systemctl daemon-reload
systemctl restart docker
docker login harbor.example.com
```

### 自签 CA 证书

如果 Harbor 是 HTTPS 自签证书，更推荐让 Docker 信任 CA：

```bash
sudo mkdir -p /etc/docker/certs.d/harbor.example.com
sudo cp ca.crt /etc/docker/certs.d/harbor.example.com/ca.crt
sudo systemctl restart docker
docker login harbor.example.com
```

## containerd 配置

本课程集群运行时为 containerd，Kubernetes 节点拉取私有镜像时需单独配置 containerd。推荐统一使用 `hosts.toml`，并确保 `/etc/containerd/config.toml` 已启用 registry hosts 配置目录。

先检查是否已配置 `config_path`：

```bash
grep -n "config_path" /etc/containerd/config.toml
```

如果没有输出，需要按 containerd 版本补充配置。

containerd 1.x 常见位置：

```toml
[plugins."io.containerd.grpc.v1.cri".registry]
  config_path = "/etc/containerd/certs.d"
```

containerd 2.x 常见位置：

```toml
[plugins.'io.containerd.cri.v1.images'.registry]
  config_path = "/etc/containerd/certs.d"
```

### HTTP Harbor

HTTP 测试仓库可配置：

```bash
sudo mkdir -p /etc/containerd/certs.d/harbor.example.com

sudo tee /etc/containerd/certs.d/harbor.example.com/hosts.toml >/dev/null <<'EOF'
server = "http://harbor.example.com"

[host."http://harbor.example.com"]
  capabilities = ["pull", "resolve", "push"]
  skip_verify = true
EOF
```

### 自签 HTTPS Harbor

HTTPS 自签证书推荐配置 CA，而不是跳过校验：

```bash
sudo mkdir -p /etc/containerd/certs.d/harbor.example.com
sudo cp ca.crt /etc/containerd/certs.d/harbor.example.com/ca.crt

sudo tee /etc/containerd/certs.d/harbor.example.com/hosts.toml >/dev/null <<'EOF'
server = "https://harbor.example.com"

[host."https://harbor.example.com"]
  capabilities = ["pull", "resolve", "push"]
  ca = "/etc/containerd/certs.d/harbor.example.com/ca.crt"
EOF
```

临时测试自签证书且无法分发 CA 时，才使用 `skip_verify = true`：

```toml
server = "https://harbor.example.com"

[host."https://harbor.example.com"]
  capabilities = ["pull", "resolve", "push"]
  skip_verify = true
```

重启 containerd：

```bash
sudo systemctl restart containerd
```

### 验证 containerd 拉取

```bash
sudo crictl pull harbor.example.com/base/nginx:alpine
sudo crictl images | grep harbor
```

## 镜像标签策略

| 策略 | 标签示例 | 适用场景 |
| --- | --- | --- |
| 语义版本 | `v1.0.0`、`v2.3.1` | 正式发布 |
| Git commit | `abc1234` | 开发验证 |
| 日期 + 序号 | `20260616-01` | CI/CD 构建 |
| 环境 + 版本 | `prod-v1.0.0` | 多环境区分 |

不建议生产环境依赖 `latest`——它只是一个普通标签，不保证最新，也无法定位版本。
