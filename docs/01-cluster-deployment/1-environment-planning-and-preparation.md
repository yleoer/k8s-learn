# 环境规划与基础准备

本文记录 Kubernetes 实验集群部署前的环境规划与节点基础配置，涵盖操作系统与组件版本选型、网络地址、节点角色、防火墙、swap 和内核网络参数。完成这些准备后，各节点具备安装 containerd、kubelet、kubeadm 与 kubectl 的基础条件。

## 环境基准

| 项目 | 选择 |
| --- | --- |
| 操作系统 | Ubuntu 24.04 LTS，代号 `noble` |
| Kubernetes | v1.36.x |
| 容器运行时 | containerd |
| CNI 网络插件 | Calico |
| 安装方式 | kubeadm |
| Pod 网段 | `10.244.0.0/16` |
| Service 网段 | `10.96.0.0/12` |

Kubernetes APT 仓库按小版本独立分仓，例如 `v1.36`、`v1.35`。安装 `kubelet`、`kubeadm`、`kubectl` 时，三个组件应使用同一小版本仓库，以确保版本一致性。

## 地址与版本约定

- **Pod CIDR 与 Calico IPPool 保持一致**：本文使用 Calico IPPool 显式声明 Pod 地址池，`kubeadm init` 指定的 `--pod-network-cidr` 应与 Calico IPPool 的地址范围保持一致，否则可能导致 Pod 网络不通。
- **节点通信使用稳定内网 IP**：控制平面与工作节点之间的通信应绑定固定的内网 IP，避免因 IP 变动引发集群异常。
- **组件版本保持同一小版本**：`kubelet`、`kubeadm`、`kubectl` 与控制平面组件应围绕同一 Kubernetes 小版本安装和维护，减少版本偏差带来的排障成本。

## 版本兼容性确认

组件之间的兼容范围以各官方文档为准，选定版本前先核对以下入口：

- **Kubernetes 组件偏差策略**：[Version Skew Policy](https://kubernetes.io/releases/version-skew-policy/) 说明 kubelet、kube-apiserver、kubectl 之间允许的版本偏差。kubelet 不得高于 kube-apiserver 版本，最多可以落后三个小版本。
- **Calico 支持的 Kubernetes 版本**：[Calico System requirements](https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements) 列出每个 Calico 版本测试过的 Kubernetes 版本范围，安装前确认所选 Calico 版本覆盖当前集群版本。
- **Metrics Server 兼容矩阵**：[metrics-server Compatibility Matrix](https://github.com/kubernetes-sigs/metrics-server#compatibility-matrix) 记录各版本要求的 Metrics API 版本与 Kubernetes 最低版本。
- **containerd 与 Kubernetes 的对应关系**：[containerd Kubernetes support](https://containerd.io/releases/#kubernetes-support) 说明各 containerd 版本经过验证的 Kubernetes 版本区间。

已知限制：Kubernetes 小版本仓库独立分仓，跨小版本升级需要按 [kubeadm upgrade](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/) 逐个小版本进行，不能跳版本；kubeadm 不支持降级。

## 节点规划

| 角色 | 主机名 | 示例 IP | 说明 |
| --- | --- | --- | --- |
| control-plane | `master` | `192.168.2.108` | 控制平面节点 |
| worker | `work01` | `192.168.2.109` | 工作节点 |
| worker | `work02` | `192.168.2.110` | 工作节点 |

每台节点建议至少配备 2 GiB 内存；control-plane 节点至少配备 2 核 CPU。实验环境的 worker 节点可按工作负载规模分配 CPU，磁盘空间建议预留 30 GiB 以上。

所有节点需满足以下前提条件：节点间网络互通、主机名与 IP 地址固定不变、系统时间已同步。实验环境可先以单 control-plane 加单 worker 节点的最小拓扑完成初步验证，待流程跑通后再按需扩展为多节点或高可用架构。

## 主机名和解析配置

在各节点上分别设置对应的主机名：

```bash
sudo hostnamectl set-hostname master   # 在 control-plane 节点执行
sudo hostnamectl set-hostname work01   # 在 work01 节点执行
sudo hostnamectl set-hostname work02   # 在 work02 节点执行
```

若环境中没有内部 DNS，需在所有节点的 `/etc/hosts` 中添加静态解析条目：

```bash
sudo tee -a /etc/hosts >/dev/null <<'EOF'
192.168.2.108 master
192.168.2.109 work01
192.168.2.110 work02
EOF
```

完成配置后，验证网络连通性与主机名解析：

```bash
hostname
hostname -I
ping -c 3 work01
ping -c 3 work02
```

## 系统更新

```bash
sudo apt update
sudo apt upgrade -y
sudo apt autoremove -y
sudo reboot
```

常规环境准备建议使用 `apt upgrade -y`，该命令在升级已安装软件包的同时，会尽量保持现有依赖关系不变。仅当需要处理发行版内核、系统组件升级或依赖关系调整，且确认可接受软件包被新增、替换或移除时，再改用 `apt full-upgrade -y`。例如 `linux-generic` 内核元包升级需要安装新版内核包并移除旧版时，或 `apt upgrade` 提示部分软件包 `have been kept back` 而这些包又必须更新时，`apt upgrade` 无法完成操作，需要 `apt full-upgrade` 处理。

重启后检查：

```bash
uname -r
hostname
hostname -I
date
timedatectl
ip addr
ip route
```

若需要将时区设置为国内 Asia/Shanghai：

```bash
sudo timedatectl set-timezone Asia/Shanghai
timedatectl
```

如发现主机名、IP 地址或系统时间存在异常，应先行修正，再继续后续步骤。Kubernetes 对证书有效期、节点身份及组件间通信均较为敏感，基础环境越稳定，后续排障的复杂度越低。

## 安装基础工具

```bash
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
```

## 可选：配置 sudo 免密码

个人实验环境可配置 sudo 免密码以简化操作；生产环境应根据安全规范评估后再决定是否启用。

个人喜欢使用 Vim，所以首先将 `visudo` 的默认编辑器切换为 Vim：

```bash
sudo update-alternatives --config editor
```

在交互列表中选择 `/usr/bin/vim.basic` 对应的编号。随后编辑对应用户的 sudoers 片段：

```bash
sudo visudo -f /etc/sudoers.d/<user>
```

写入以下内容（将 `<user>` 替换为实际用户名）：

```text
<user> ALL=(ALL:ALL) NOPASSWD: ALL
```

设置文件权限并验证配置生效：

```bash
sudo chmod 440 /etc/sudoers.d/<user>
sudo -k
sudo whoami
```

## 可选：Tailscale 远程访问

若需要跨网络访问或远程管理本地或内网节点，可安装 Tailscale。

以下命令在 Ubuntu 24.04 执行：

```bash
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg | \
  sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null

curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list | \
  sudo tee /etc/apt/sources.list.d/tailscale.list

sudo apt update
sudo apt install -y tailscale
sudo tailscale up
```

## 防火墙配置

实验环境可暂时关闭 UFW，以减少网络排障的干扰变量：

```bash
sudo ufw status
sudo ufw disable
sudo systemctl disable --now ufw
```

生产环境不应直接关闭防火墙，而应按节点角色放行所需端口。以 UFW 为例：

**control-plane 节点**，放行 API Server、etcd 及控制面组件端口：

```bash
sudo ufw allow 6443/tcp
sudo ufw allow 2379:2380/tcp
sudo ufw allow 10250/tcp
sudo ufw allow 10257/tcp
sudo ufw allow 10259/tcp
```

**worker 节点**，放行 kubelet、kube-proxy 健康检查及 NodePort 端口范围：

```bash
sudo ufw allow 10250/tcp
sudo ufw allow 10256/tcp
sudo ufw allow 30000:32767/tcp
sudo ufw allow 30000:32767/udp
```

**所有节点**，若使用 Calico VXLAN 模式，放行 VXLAN 端口：

```bash
sudo ufw allow 4789/udp
```

若使用 Calico BGP 模式，放行 BGP 端口：

```bash
sudo ufw allow 179/tcp
```

完成后启用防火墙并核查规则：

```bash
sudo ufw enable
sudo ufw status numbered
```

若节点上层还存在云安全组、硬件防火墙或网络 ACL，需同步放行上述端口。

## 禁用 swap

立即关闭当前会话的 swap：

```bash
sudo swapoff -a
swapon --show
```

永久禁用需编辑 `/etc/fstab`，注释掉 swap 相关条目：

```bash
sudo vim /etc/fstab
```

将 swap 行注释，例如：

```text
# /swap.img none swap sw 0 0
```

修改完成后，验证 `/etc/fstab` 无语法错误：

```bash
sudo mount -a
```

禁用 swap 是为了确保 kubelet 能够依据真实内存压力做出准确的资源管理与 Pod 驱逐决策，避免因 swap 介入导致内存不足时的行为不可预期。

## 配置内核模块和网络参数

加载 containerd 与 Pod 网络所需的内核模块，并配置开机自动加载：

```bash
sudo tee /etc/modules-load.d/k8s.conf >/dev/null <<'EOF'
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

配置 IPv4 转发及网桥流量过滤参数：

```bash
sudo tee /etc/sysctl.d/k8s.conf >/dev/null <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

验证模块已加载、参数已生效：

```bash
lsmod | grep -E 'overlay|br_netfilter'
sysctl net.bridge.bridge-nf-call-iptables
sysctl net.bridge.bridge-nf-call-ip6tables
sysctl net.ipv4.ip_forward
```

各参数的作用说明：

- `overlay`：containerd 默认存储驱动 OverlayFS 的内核依赖模块。
- `br_netfilter`：使经过网桥的流量进入 netfilter 过滤链，确保 Pod 网络流量能被 iptables 正确处理。
- `net.ipv4.ip_forward=1`：开启内核 IP 转发，是跨节点 Pod 通信的基本前提。
- `net.bridge.bridge-nf-call-ip6tables=1`：使网桥上的 IPv6 流量进入 ip6tables 过滤链，仅在节点启用 IPv6 时实际参与流量处理；本集群使用 IPv4 单栈，保留该参数是为兼容默认配置，不影响现有网络行为。
