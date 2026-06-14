# Calico 网络插件安装

本节安装 Calico 网络插件。没有 CNI 时，节点通常会保持 `NotReady`，Pod 也无法跨节点通信。

## 安装 Calico Operator

仅在 control-plane 节点执行：

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/v1_crd_projectcalico_org.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/tigera-operator.yaml
```

## 创建 Calico 自定义资源

创建配置文件：

```bash
vim calico-custom-resources.yaml
```

写入：

```yaml
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
      - blockSize: 26
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

如果提示 `resource mapping not found for name`，通常是 Tigera Operator 的 CRD 还没有安装完成。等待几十秒后重试：

```bash
kubectl get crd | grep tigera
kubectl create -f calico-custom-resources.yaml
```

## 查看安装状态

```bash
kubectl get pods -n tigera-operator
kubectl get pods -n calico-system
kubectl get nodes -o wide
```

所有 Calico Pod 正常运行后，节点应从 `NotReady` 变为 `Ready`。

## CIDR 一致性检查

查看 kubeadm 中记录的 Pod CIDR：

```bash
kubectl -n kube-system get cm kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' | grep -A 5 networking
```

查看 Calico IPPool：

```bash
kubectl get ippool -A -o yaml
```

如果 kubeadm 初始化时使用的是 `10.244.0.0/16`，Calico 中也应使用：

```yaml
cidr: 10.244.0.0/16
```
