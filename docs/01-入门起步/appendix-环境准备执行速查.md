# 环境准备执行速查

## 所有节点：系统更新

```bash
sudo apt update
sudo apt full-upgrade -y
sudo reboot
```

## 所有节点：内核与 swap

```bash
sudo swapoff -a
sudo modprobe overlay
sudo modprobe br_netfilter
sudo sysctl --system
```

## 所有节点：运行时与 Kubernetes 组件

```bash
sudo apt install -y containerd.io
sudo systemctl enable --now containerd
sudo apt install -y kubelet kubeadm kubectl cri-tools
sudo apt-mark hold kubelet kubeadm kubectl
```

## control-plane 节点：初始化

```bash
sudo kubeadm init \
  --kubernetes-version v1.36.1 \
  --image-repository registry.aliyuncs.com/google_containers \
  --pod-network-cidr 10.244.0.0/16 \
  --cri-socket unix:///run/containerd/containerd.sock

mkdir -p "$HOME/.kube"
sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
```

## control-plane 节点：安装 Calico

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/v1_crd_projectcalico_org.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/tigera-operator.yaml
kubectl create -f calico-custom-resources.yaml
```

## worker 节点：加入集群

```bash
sudo kubeadm join <control-plane-ip>:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

## 最终检查

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
```
