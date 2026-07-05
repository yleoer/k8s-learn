# 集群部署

本章是全书的起点，从零准备主机环境，搭建一套可运行、可验证、便于反复调整的 Kubernetes 实验集群。

本章以 kubeadm 为安装工具、containerd 为容器运行时、Calico 为 CNI 网络插件、Metrics Server 为资源指标组件，形成从主机准备到集群验证的完整部署链路。后续 Pod、Service、Ingress、存储、调度和可观测性等记录均基于这一实验环境展开。

## 部署脉络

本章最终完成一套单 control-plane、多 worker 的 Kubernetes 实验集群。整体部署路径按依赖关系收束为五个层面：

- **主机层**：固定主机名和内网地址，完成系统更新、时间同步、基础工具安装、swap 关闭、内核模块加载和网络参数配置。
- **运行时层**：所有节点安装 containerd，通过 CRI socket 供 kubelet 调用；确保 kubelet 与 containerd 的 cgroup driver 保持一致。
- **控制面层**：使用 kubeadm 初始化 API Server、etcd、controller-manager、scheduler、kube-proxy 和 CoreDNS 等核心组件。
- **网络层**：安装 Calico 作为 CNI 网络插件，使 Pod 网络符合 Kubernetes 网络模型。
- **验证层**：接入 worker 节点，部署 Metrics Server，通过测试 Deployment、Service、NodePort、集群内 DNS 和 `kubectl top` 验证调度、网络、服务转发和资源指标链路。

## 组件职责

- **kubeadm** 负责节点初始化、控制平面组件部署、集群引导、证书管理和版本升级等集群生命周期操作。
- **containerd** 是集群的 CRI 运行时，负责为 kubelet 创建 Pod sandbox、拉取镜像并管理容器进程。
- **Calico** 承担 Pod 网络与节点间通信的实现。它解决的是 CNI 网络插件层的问题。
- **kube-proxy** 以 DaemonSet 运行在各节点，负责 Service 的负载均衡实现，默认通过 iptables 规则将 Service 流量转发到后端 Pod，也可配置为 nftables 模式；IPVS 模式自 v1.35 起已弃用。
- **CoreDNS** 为集群内的 Service 与 Pod 提供 DNS 解析，使 Pod 可以通过 DNS 名称访问其他 Service。
- **Metrics Server** 提供 `metrics.k8s.io` 资源指标 API，使 `kubectl top`、HPA 和 VPA 能够获取节点与 Pod 的 CPU、内存用量。

## 参考

- [Creating a cluster with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)
- [Container Runtimes](https://kubernetes.io/docs/setup/production-environment/container-runtimes/)
- [Network Plugins](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/)
- [Resource metrics pipeline](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)
