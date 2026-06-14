# Worker 节点加入与单节点调度

control-plane 初始化成功后，可以把 worker 节点加入集群。加入前要确认 worker 节点已经完成系统基础配置、containerd 安装和 Kubernetes 组件安装。

## Worker 加入集群

在 worker 节点执行 kubeadm init 输出的 join 命令，示例：

```bash
sudo kubeadm join 192.168.1.10:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

如果初始化时指定了 CRI socket，也可以显式带上：

```bash
sudo kubeadm join 192.168.1.10:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --cri-socket unix:///run/containerd/containerd.sock
```

如果忘记保存 join 命令，可以在 control-plane 节点重新生成：

```bash
kubeadm token create --print-join-command
```

回到 control-plane 节点检查：

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

## 单节点集群允许调度 Pod

如果只有一个 control-plane 节点，并且希望它同时运行业务 Pod，可以去掉控制平面污点：

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

检查污点：

```bash
kubectl describe node "$(hostname)" | grep -i taints
```

## kubectl 自动补全

```bash
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'alias k=kubectl' >> ~/.bashrc
echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
source ~/.bashrc
```
