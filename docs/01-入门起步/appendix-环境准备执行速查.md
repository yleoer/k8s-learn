# 环境准备执行速查

本页仅保留关键执行步骤与顺序，适合在理解前文内容后快速回顾或复现环境。首次搭建请按正文各节逐步操作，切勿跳步执行。

## 所有节点：系统初始化与内核配置

```bash
sudo apt update
sudo apt upgrade -y
sudo reboot

sudo swapoff -a
sudo modprobe overlay
sudo modprobe br_netfilter
sudo sysctl --system
```

## 所有节点：安装运行时与 Kubernetes 组件

```bash
sudo apt install -y containerd.io
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl enable --now containerd

sudo apt install -y kubelet kubeadm kubectl cri-tools
sudo apt-mark hold kubelet kubeadm kubectl
```

## control-plane 节点：集群初始化

```bash
sudo kubeadm init \
  --kubernetes-version v1.36.2 \
  --image-repository registry.aliyuncs.com/google_containers \
  --pod-network-cidr 10.244.0.0/16 \
  --service-cidr 10.96.0.0/12 \
  --cri-socket unix:///run/containerd/containerd.sock

mkdir -p "$HOME/.kube"
sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
```

## control-plane 节点：安装 Calico 网络插件

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/v1_crd_projectcalico_org.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/tigera-operator.yaml
kubectl create -f calico-custom-resources.yaml
```

## worker 节点：加入集群

```bash
sudo kubeadm join <control-plane-ip>:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --cri-socket unix:///run/containerd/containerd.sock
```

## 最终检查

```bash
# 确认所有节点 Ready
kubectl get nodes -o wide

# 确认所有系统 Pod 正常运行
kubectl get pods -A -o wide

# 部署测试应用并验证 NodePort 访问
kubectl create deployment nginx --image=nginx:1.27
kubectl expose deployment nginx --port=80 --type=NodePort
kubectl get deploy,pod,svc -o wide
```
