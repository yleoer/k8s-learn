# 环境准备执行速查

本页仅保留关键执行步骤与顺序，用于快速回顾或复现实验环境。首次搭建仍应按正文各节逐步操作，避免跳过必要检查。

## 所有节点：主机与系统初始化

按节点角色分别设置主机名：

```bash
sudo hostnamectl set-hostname master   # 在 control-plane 节点执行
sudo hostnamectl set-hostname work01   # 在 work01 节点执行
sudo hostnamectl set-hostname work02   # 在 work02 节点执行
```

所有节点写入静态解析：

```bash
sudo tee -a /etc/hosts >/dev/null <<'EOF'
192.168.2.108 master
192.168.2.109 work01
192.168.2.110 work02
EOF
```

```bash
sudo apt update
sudo apt upgrade -y
sudo apt autoremove -y
sudo reboot
```

重启并重新登录后继续执行：

```bash
hostname
hostname -I
date

sudo apt update
sudo apt install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gpg \
  gnupg \
  lsb-release \
  vim \
  bash-completion \
  socat \
  conntrack \
  ipset \
  ipvsadm

sudo swapoff -a
swapon --show

sudo vim /etc/fstab   # 注释 swap 行
sudo mount -a

sudo tee /etc/modules-load.d/k8s.conf >/dev/null <<'EOF'
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

sudo tee /etc/sysctl.d/k8s.conf >/dev/null <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
lsmod | grep -E 'overlay|br_netfilter'
sysctl net.bridge.bridge-nf-call-iptables
sysctl net.bridge.bridge-nf-call-ip6tables
sysctl net.ipv4.ip_forward
```

## 所有节点：安装运行时与 Kubernetes 组件

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

sudo apt update
sudo apt install -y containerd.io
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd
sudo systemctl status containerd --no-pager

# 如需配置镜像加速（参见正文「可选：配置镜像加速」），在此处添加 hosts.toml 配置

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt update
if ! command -v crictl >/dev/null 2>&1; then
  sudo apt install -y cri-tools
fi

crictl --version

sudo tee /etc/crictl.yaml >/dev/null <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

sudo systemctl restart containerd
sudo crictl info
sudo crictl pull registry.k8s.io/pause:3.10.2   # pause 版本与 kubeadm 后续拉取的控制面镜像版本一致
sudo crictl images
```

安装 Kubernetes 组件并锁定版本：

```bash
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

kubeadm version
kubectl version --client
kubelet --version
crictl --version
```

## control-plane 节点：集群初始化

```bash
sudo kubeadm config images list
sudo kubeadm config images pull

# 中国内地访问 registry.k8s.io 较慢时可预拉取国内镜像仓库中的控制面镜像。
sudo kubeadm config images pull \
  --image-repository registry.aliyuncs.com/google_containers

sudo kubeadm init \
  --kubernetes-version "$(kubeadm version -o short)" \
  --pod-network-cidr 10.244.0.0/16 \
  --service-cidr 10.96.0.0/12 \
  --cri-socket unix:///run/containerd/containerd.sock

mkdir -p "$HOME/.kube"
sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

kubectl get no -o wide
kubectl get po -A
```

## control-plane 节点：安装 Calico 网络插件

本附录重复给出正文[安装 Calico](./3-集群初始化与集群插件.md#安装-calico)使用的完整 `calico-custom-resources.yaml`，便于按顺序执行：

```yaml [calico-custom-resources.yaml]
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
      - blockSize: 26
        name: default-ipv4-ippool
        cidr: 10.244.0.0/16
        encapsulation: VXLAN
        natOutgoing: Enabled
        nodeSelector: all()
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
```

首次安装时执行：

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.1/manifests/v1_crd_projectcalico_org.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.1/manifests/tigera-operator.yaml
kubectl create -f calico-custom-resources.yaml
```

## worker 节点：加入集群

```bash
sudo kubeadm join <control-plane-ip>:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --cri-socket unix:///run/containerd/containerd.sock
```

## control-plane 节点：安装 Metrics Server

```bash
kubectl create -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.8.1/components.yaml
kubectl -n kube-system rollout status deploy/metrics-server
kubectl get apiservice v1beta1.metrics.k8s.io

# kubeadm 实验环境出现 kubelet x509 证书错误时使用
kubectl -n kube-system patch deploy metrics-server \
  --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl -n kube-system rollout restart deployment metrics-server
kubectl -n kube-system rollout status deployment metrics-server
```

## 最终检查

```bash
# 确认所有节点 Ready
kubectl get no -o wide

# 确认所有系统 Pod 正常运行
kubectl get po -A -o wide

# 确认资源指标 API 可用
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl top no
kubectl top po -A

# 部署测试应用并验证 NodePort 访问
kubectl create deploy sample-nginx --image=nginx:1.31-alpine
kubectl expose deploy sample-nginx --port=80 --type=NodePort
kubectl get deploy,pod,svc -l app=sample-nginx -o wide
NODE_PORT=$(kubectl get svc sample-nginx -o jsonpath='{.spec.ports[0].nodePort}')
curl "http://master:${NODE_PORT}"
kubectl run sample-curl --rm -i --restart=Never \
  --image=curlimages/curl:8.21.0 \
  -- curl -I --max-time 10 http://sample-nginx.default.svc.cluster.local

kubectl delete svc sample-nginx
kubectl delete deploy sample-nginx
```
