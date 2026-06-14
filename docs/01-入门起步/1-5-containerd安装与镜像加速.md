# containerd 安装与镜像加速

Kubernetes 通过 CRI 和容器运行时通信。这里使用 containerd，并配置 `crictl` 作为排查工具。

## 添加 Docker APT 源

所有节点执行：

```bash
sudo apt update
sudo apt install -y ca-certificates curl gpg
sudo install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
```

国内网络环境可替换为清华源：

```bash
curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
```

## 安装 containerd

```bash
sudo apt update
sudo apt install -y containerd.io
```

查看版本：

```bash
containerd --version
apt policy containerd.io
```

## 生成并调整配置

```bash
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
```

启用 systemd cgroup driver：

```bash
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
```

启用 registry hosts 配置目录。containerd 1.x 常见配置路径：

```toml
[plugins."io.containerd.grpc.v1.cri".registry]
  config_path = "/etc/containerd/certs.d"
```

containerd 2.x 常见配置路径：

```toml
[plugins.'io.containerd.cri.v1.images'.registry]
  config_path = "/etc/containerd/certs.d"
```

检查当前配置中实际的 registry 段：

```bash
grep -n "registry" -A 8 /etc/containerd/config.toml
```

启动并设置开机自启：

```bash
sudo systemctl restart containerd
sudo systemctl enable containerd
sudo systemctl status containerd --no-pager
```

## 配置镜像加速

```bash
sudo mkdir -p /etc/containerd/certs.d/docker.io
sudo mkdir -p /etc/containerd/certs.d/registry.k8s.io
sudo mkdir -p /etc/containerd/certs.d/quay.io
sudo mkdir -p /etc/containerd/certs.d/ghcr.io
```

Docker Hub：

```bash
sudo tee /etc/containerd/certs.d/docker.io/hosts.toml >/dev/null <<'EOF'
server = "https://registry-1.docker.io"

[host."https://docker.1ms.run"]
  capabilities = ["pull", "resolve"]

[host."https://docker.m.daocloud.io"]
  capabilities = ["pull", "resolve"]

[host."https://registry-1.docker.io"]
  capabilities = ["pull", "resolve"]
EOF
```

Kubernetes 官方镜像仓库：

```bash
sudo tee /etc/containerd/certs.d/registry.k8s.io/hosts.toml >/dev/null <<'EOF'
server = "https://registry.k8s.io"

[host."https://k8s.m.daocloud.io"]
  capabilities = ["pull", "resolve"]

[host."https://registry.k8s.io"]
  capabilities = ["pull", "resolve"]
EOF
```

重启 containerd：

```bash
sudo systemctl restart containerd
```

## 配置 crictl

```bash
sudo tee /etc/crictl.yaml >/dev/null <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF
```

测试拉取镜像：

```bash
sudo crictl pull docker.io/library/nginx:latest
sudo crictl pull registry.k8s.io/pause:3.10
sudo crictl images
```
