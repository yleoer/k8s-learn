# 内核网络与 Swap 配置

本节在所有节点执行，目标是让 Linux 内核、网络转发和 swap 状态满足 Kubernetes 与 containerd 的运行要求。

## 关闭 swap

立即关闭：

```bash
sudo swapoff -a
swapon --show
```

如果 `swapon --show` 没有输出，说明当前 swap 已关闭。

永久禁用：

```bash
sudo vim /etc/fstab
```

找到类似下面的 swap 行：

```text
/swap.img none swap sw 0 0
UUID=xxxx-xxxx none swap sw 0 0
```

在行首加 `#` 注释：

```text
# /swap.img none swap sw 0 0
```

验证 `/etc/fstab` 没有语法错误：

```bash
sudo mount -a
```

关闭 swap 的原因：

- Kubernetes 依赖 Pod 的 `requests` 和 `limits` 做资源管理，swap 会让内存压力判断变得不准确。
- swap 使用磁盘模拟内存，性能不可预测，Pod 可能不立即失败，而是变得非常慢。
- kubelet 需要根据真实内存压力做驱逐决策，开启 swap 会干扰判断。

## 加载内核模块

```bash
sudo tee /etc/modules-load.d/k8s.conf >/dev/null <<'EOF'
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

检查是否加载成功：

```bash
lsmod | grep -E 'overlay|br_netfilter'
```

## 配置 sysctl

```bash
sudo tee /etc/sysctl.d/k8s.conf >/dev/null <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

检查结果：

```bash
sysctl net.bridge.bridge-nf-call-iptables
sysctl net.bridge.bridge-nf-call-ip6tables
sysctl net.ipv4.ip_forward
```

这些配置的作用：

- `overlay`：containerd 常用的 OverlayFS 存储驱动依赖它。
- `br_netfilter`：让 Linux bridge 流量经过 iptables 或 nftables 处理。
- `net.bridge.bridge-nf-call-iptables=1`：让桥接 IPv4 流量进入 iptables 规则。
- `net.bridge.bridge-nf-call-ip6tables=1`：让桥接 IPv6 流量进入 ip6tables 规则。
- `net.ipv4.ip_forward=1`：允许节点转发 IPv4 流量，Pod 跨节点通信需要。
