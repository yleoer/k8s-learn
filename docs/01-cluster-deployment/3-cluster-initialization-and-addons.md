# 集群初始化与集群插件

本文依次完成 control-plane 初始化、kubectl 配置、Calico 网络插件安装、worker 节点接入和 Metrics Server 部署。

全部步骤完成后，集群中所有节点应进入 `Ready` 状态，Pod 网络正常互通，并可通过 `kubectl top` 查看基础资源指标。

## 初始化 control-plane

> [!WARNING]
> **本小节命令仅在 `master` 节点执行，不要在 worker 节点运行 `kubeadm init`。**

初始化前，先列出并提前拉取 kubeadm 所需的控制平面镜像，以便确认镜像可达性、提前发现网络问题：

```bash
sudo kubeadm config images list
sudo kubeadm config images pull
```

::: details 镜像版本类似如下

```bash
$ sudo kubeadm config images list
registry.k8s.io/kube-apiserver:v1.36.2
registry.k8s.io/kube-controller-manager:v1.36.2
registry.k8s.io/kube-scheduler:v1.36.2
registry.k8s.io/kube-proxy:v1.36.2
registry.k8s.io/coredns/coredns:v1.14.2
registry.k8s.io/pause:3.10.2
registry.k8s.io/etcd:3.6.8-0
```

:::

若访问 `registry.k8s.io` 较慢，可在 kubeadm 命令指定国内镜像仓库：

```bash
sudo kubeadm config images pull \
  --image-repository registry.aliyuncs.com/google_containers
```

执行集群初始化：

```bash
sudo kubeadm init \
  --kubernetes-version "$(kubeadm version -o short)" \
  --pod-network-cidr 10.244.0.0/16 \
  --service-cidr 10.96.0.0/12 \
  --cri-socket unix:///run/containerd/containerd.sock
```

关键参数说明：

- `--kubernetes-version`：建议与已安装的 kubeadm 小版本保持一致，用 `kubeadm version` 确认版本后填入对应值。
- `--pod-network-cidr`：Pod 网段，本文配置应与后续 Calico IPPool 的 CIDR 完全一致，否则 Pod 网络可能无法正常工作。
- `--service-cidr`：Service 虚拟 IP 网段。
- `--cri-socket`：显式指定 containerd 的 CRI socket 路径，避免多运行时环境下的歧义。

> [!TIP]
> 初始化成功后，**务必保存输出末尾的 `kubeadm join ...` 命令**，后续 worker 节点加入集群时需要用到。

## 配置 kubectl

> [!WARNING]
> **本小节命令仅在 `master` 节点执行。**

将集群访问凭证复制到当前用户的默认配置路径：

```bash
mkdir -p "$HOME/.kube"
sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
```

验证 kubectl 可正常访问集群：

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

此时节点通常处于 `NotReady` 状态，这是正常现象——CNI 网络插件尚未安装，节点网络尚未就绪。

## 安装 Calico

::: warning
**本小节命令仅在 `master` 节点执行。**
:::

依次安装 Calico CRD 和 Tigera Operator：

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/v1_crd_projectcalico_org.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/tigera-operator.yaml
```

如果 `raw.githubusercontent.com` 无法访问，可先将 YAML 下载到本地后再 apply，无需在集群节点上连接该域名：

```bash
# 在可以访问 GitHub 的机器上执行
curl -fsSL -o calico-crd.yaml https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/v1_crd_projectcalico_org.yaml
curl -fsSL -o tigera-operator.yaml https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/tigera-operator.yaml

# 将这两个文件传输到 control-plane 节点后 apply
kubectl create -f calico-crd.yaml
kubectl create -f tigera-operator.yaml
```

本文通过 Tigera Operator 安装 Calico，而非直接 apply Calico 的 DaemonSet 清单。Operator 模式将 Calico 组件的生命周期（部署、配置、升级、扩缩）统一管理，后续调整网络参数或升级 Calico 版本时只需修改 `Installation` 资源，Operator 自行完成组件更新。

这里不直接使用 Calico 默认的 `custom-resources.yaml`，而是手动声明 `Installation` 资源，目的是将 `ipPools.cidr` 明确设置为与 `kubeadm init` 中 `--pod-network-cidr` 一致的网段。若两者不一致，Pod 可能被分配到错误网段，节点也可能长时间停留在 `NotReady` 状态。

创建 `calico-custom-resources.yaml`：

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

应用配置：

```bash
kubectl create -f calico-custom-resources.yaml
```

若提示 `resource mapping not found`，通常是 Tigera Operator 的 CRD 尚未完成注册。等待约 30 秒后重试：

```bash
kubectl get crd | grep tigera
kubectl create -f calico-custom-resources.yaml
```

查看 Calico 各组件的启动状态：

```bash
kubectl get pods -n tigera-operator
kubectl get pods -n calico-system
kubectl get nodes -o wide
```

若 Calico 未能正常启动，先区分 Operator 管理的状态资源和配置资源：

- `TigeraStatus`：Tigera Operator 写入的状态资源，用于汇总 Calico 相关组件的可用性、部署进度和异常信息。
- `Installation`：Tigera Operator 的核心配置资源，记录 Calico 安装方式、网络模式、IPPool、封装方式和组件参数等期望状态。

按以下顺序排查 Operator 和 Installation 状态：

```bash
kubectl get tigerastatus
kubectl describe tigerastatus calico
kubectl get installation default -o yaml
kubectl describe installation default
kubectl logs -n tigera-operator deploy/tigera-operator --tail=100
```

常见问题包括：

- `ipPools.cidr` 与 `--pod-network-cidr` 不一致。
- 节点防火墙阻断了 VXLAN（UDP 4789）、BGP（TCP 179）或 kubelet 通信端口。
- `br_netfilter` 模块或 `ip_forward` 内核参数未生效。
- 节点时间不同步，导致证书校验或组件通信异常。
- 镜像拉取失败，Calico Pod 持续处于 `ImagePullBackOff` 状态。

如需在实验环境中重新安装 Calico，可按以下顺序清理现有资源（生产环境请勿直接操作，删除 CNI 会短暂中断集群网络）：

```bash
kubectl delete -f calico-custom-resources.yaml --ignore-not-found
kubectl delete -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/tigera-operator.yaml --ignore-not-found
kubectl delete -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/v1_crd_projectcalico_org.yaml --ignore-not-found
```

所有 Calico Pod 进入 `Running` 状态后，节点将从 `NotReady` 变更为 `Ready`。

### CIDR 一致性检查

集群网络就绪后，核查 kubeadm 记录的 Pod CIDR 与 Calico IPPool 是否完全一致。

查看 kubeadm 配置中记录的网络参数：

```bash
kubectl -n kube-system get cm kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' | grep -A 5 networking
```

查看 Calico IPPool 的 CIDR 配置：

```bash
kubectl get ippool -o yaml
```

两处 CIDR 应完全相同，例如均为 `10.244.0.0/16`。若存在差异，需重新安装 Calico 并修正配置。

## 加入 worker 节点

> [!WARNING]
> 本小节命令在各 worker 节点上分别执行。

在每台 worker 节点上执行 kubeadm init 输出的 join 命令：

```bash
sudo kubeadm join 192.168.2.108:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --cri-socket unix:///run/containerd/containerd.sock
```

若初始化时未保存 join 命令，可在 control-plane 节点重新生成：

```bash
kubeadm token create --print-join-command
```

worker 节点加入后，回到 control-plane 节点确认集群状态：

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

## 安装 Metrics Server

Metrics Server 从各节点 kubelet 采集 CPU、内存等资源指标，并通过 `metrics.k8s.io` API 暴露给 `kubectl top` 和 HPA。它只提供资源指标管道，不替代 Prometheus、日志系统或完整监控告警平台。

> [!WARNING]
> **本小节命令仅在 `master` 节点执行。**

部署官方组件清单。本文固定使用 Metrics Server v0.8.0。

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.8.0/components.yaml
```

等待 Deployment 就绪：

```bash
kubectl -n kube-system rollout status deploy/metrics-server
kubectl -n kube-system get deploy metrics-server
kubectl get apiservice v1beta1.metrics.k8s.io
```

指标 API 正常后，查看节点和 Pod 的实时资源使用量：

```bash
kubectl top nodes
kubectl top pods -A
```

> [!NOTE]
> kubeadm 实验环境中 kubelet 默认使用自签证书，kubelet serving certificate 通常不包含节点 IP 地址，Metrics Server 连接 kubelet 时报 `x509` 证书校验错误。如果 `kubectl top` 报错，跳转到下方「Metrics Server 证书问题」处理后再回来验证。

如果 `APIService` 长时间处于 `False`，或 `kubectl top` 报错，需要先查看 Metrics Server 日志：

```bash
kubectl -n kube-system logs deploy/metrics-server --tail=100
kubectl describe apiservice v1beta1.metrics.k8s.io
```

在 kubeadm 实验环境中，常见问题是 kubelet serving certificate 不包含节点 IP，日志中会出现 `x509` 证书校验错误。实验环境可追加 `--kubelet-insecure-tls` 跳过 kubelet 证书校验：

```bash
kubectl -n kube-system patch deployment metrics-server \
  --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

kubectl -n kube-system rollout restart deployment metrics-server
kubectl -n kube-system rollout status deployment metrics-server
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl top nodes
```

`--kubelet-insecure-tls` 仅适合实验环境。生产环境应使用由集群 CA 签发且包含正确 SAN 的 kubelet serving certificate，并确保 control-plane 能访问 Metrics Server Pod，Metrics Server 能访问各节点 kubelet 的 `10250` 端口。

## 单节点集群允许调度 Pod

若实验环境只有一个 control-plane 节点，且需要在其上直接运行业务 Pod，需移除控制平面污点：

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

验证污点已移除：

```bash
kubectl describe node "$(hostname)" | grep -i taints
```

## kubectl 自动补全

**Bash** 可将补全脚本和别名写入 `~/.bashrc`：

```bash
echo 'alias k=kubectl' >> ~/.bashrc
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
source ~/.bashrc
```

**Zsh（oh-my-zsh）** 可将补全脚本作为自定义插件加载：

```bash
mkdir -p ~/.oh-my-zsh/custom/plugins/kubectl
kubectl completion zsh > ~/.oh-my-zsh/custom/plugins/kubectl/kubectl.zsh
```

在 `~/.zshrc` 的 `plugins` 列表中加入 `kubectl`：

```zsh
plugins=(git kubectl)
```

重新加载配置：

```bash
source ~/.zshrc
```

::: details 最终 nodes 和 pods 输出类似如下

```text
$ kubectl get no -o wide
NAME     STATUS   ROLES           AGE     VERSION   INTERNAL-IP     EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION              CONTAINER-RUNTIME
master   Ready    control-plane   3d21h   v1.36.2   192.168.2.108   <none>        Ubuntu 24.04.4 LTS   6.8.0-124-generic (amd64)   containerd://2.2.4
work01   Ready    <none>          17d     v1.36.2   192.168.2.109   <none>        Ubuntu 24.04.4 LTS   6.8.0-124-generic (amd64)   containerd://2.2.4
work02   Ready    <none>          17d     v1.36.2   192.168.2.110   <none>        Ubuntu 24.04.4 LTS   6.8.0-124-generic (amd64)   containerd://2.2.4

$ kubectl get po -A
NAMESPACE          NAME                                       READY   STATUS    RESTARTS       AGE
calico-apiserver   calico-apiserver-5b89d6564d-6qgwv          1/1     Running   4 (67m ago)    20d
calico-apiserver   calico-apiserver-5b89d6564d-bkw8x          1/1     Running   4 (67m ago)    20d
calico-system      calico-kube-controllers-75f665b4f6-gmcq9   1/1     Running   4 (67m ago)    20d
calico-system      calico-node-6xv5x                          1/1     Running   4 (67m ago)    20d
calico-system      calico-node-8m5m6                          1/1     Running   5 (68m ago)    20d
calico-system      calico-node-t4mxk                          1/1     Running   4 (68m ago)    20d
calico-system      calico-typha-7f8ffbb8-bjdrk                1/1     Running   4 (68m ago)    20d
calico-system      calico-typha-7f8ffbb8-ssnhh                1/1     Running   5 (68m ago)    20d
calico-system      csi-node-driver-jtn4l                      2/2     Running   10 (68m ago)   20d
calico-system      csi-node-driver-kh22j                      2/2     Running   8 (68m ago)    20d
calico-system      csi-node-driver-tqs2z                      2/2     Running   8 (67m ago)    20d
kube-system        coredns-589f44dc88-g44wq                   1/1     Running   4 (67m ago)    20d
kube-system        coredns-589f44dc88-rskr5                   1/1     Running   4 (67m ago)    20d
kube-system        etcd-master                                1/1     Running   4 (67m ago)    20d
kube-system        kube-apiserver-master                      1/1     Running   5 (67m ago)    20d
kube-system        kube-controller-manager-master             1/1     Running   10 (67m ago)   20d
kube-system        kube-proxy-qqjkm                           1/1     Running   4 (67m ago)    20d
kube-system        kube-proxy-qr8gw                           1/1     Running   4 (68m ago)    20d
kube-system        kube-proxy-qzxnt                           1/1     Running   5 (68m ago)    20d
kube-system        kube-scheduler-master                      1/1     Running   10 (67m ago)   20d
kube-system        metrics-server-564b7c8ccc-kfz5r            1/1     Running   1 (68m ago)    4d13h
tigera-operator    tigera-operator-579877d476-xz84d           1/1     Running   13 (68m ago)   20d
```

:::
