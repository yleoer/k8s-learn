# Kubernetes 组件安装

本节在所有节点安装 `kubelet`、`kubeadm`、`kubectl` 和 `cri-tools`。

## 添加 Kubernetes APT 源

官方源：

```bash
sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl gpg
sudo mkdir -p /etc/apt/keyrings

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list
```

国内网络环境可使用阿里云镜像源：

```bash
curl -fsSL https://mirrors.aliyun.com/kubernetes-new/core/stable/v1.36/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://mirrors.aliyun.com/kubernetes-new/core/stable/v1.36/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list
```

## 安装组件

```bash
sudo apt update
sudo apt install -y kubelet kubeadm kubectl cri-tools
```

锁定版本，避免系统升级时自动升级 Kubernetes：

```bash
sudo apt-mark hold kubelet kubeadm kubectl
```

查看版本：

```bash
kubeadm version
kubectl version --client
kubelet --version
crictl --version
```

## 组件职责

- `kubeadm`：负责初始化集群、生成证书和配置、加入节点。
- `kubelet`：运行在每个节点上，负责管理 Pod 生命周期。
- `kubectl`：客户端工具，用来向 API Server 发起操作请求。
- `cri-tools`：提供 `crictl`，用于检查 CRI runtime。

安装完成后建议拍摄 `before-kubeadm` 快照，后续初始化失败时可以快速回滚。
