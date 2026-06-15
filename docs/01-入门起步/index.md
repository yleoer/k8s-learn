# 入门起步

本阶段从零准备一套可运行、可验证、便于反复练习的 Kubernetes 实验集群。先把 kubeadm、containerd、Calico 和基础排障链路跑通，为后续 Pod、Service、Ingress、存储、调度和可观测性章节打基础。本阶段的任务是：

- 明确节点角色、版本、网段和镜像源等关键约定。
- 在 Ubuntu 24.04 上完成 Kubernetes 节点的系统初始化。
- 安装并配置 containerd、kubelet、kubeadm、kubectl 和 crictl。
- 使用 kubeadm 初始化 control-plane，并让 worker 节点加入集群。
- 安装 Calico 网络插件，使节点和 Pod 进入可用状态。
- 部署一个测试应用，验证调度、Pod 网络和 NodePort 访问链路。
- 使用常用命令定位 kubelet、containerd、CNI、镜像拉取等基础问题。

## 目录

| 文档 | 内容 |
| --- | --- |
| [环境规划与版本选择](./1-环境规划与版本选择) | 明确版本、节点、网段、主机名和快照策略 |
| [基础环境准备](./2-基础环境准备) | 完成系统更新、基础工具、远程访问、内核网络和 swap 配置 |
| [运行时与组件安装](./3-运行时与组件安装) | 安装 containerd、配置镜像加速、安装 kubeadm 相关组件 |
| [集群初始化与网络插件](./4-集群初始化与网络插件) | 初始化 control-plane、安装 Calico、加入 worker 节点 |
| [验证集群与常见排障](./5-验证集群与常见排障) | 部署测试应用并掌握第一轮排障命令 |
| [Docker 并行使用](./appendix-Docker并行使用) | 在 containerd 集群节点上额外使用 Docker |
| [环境准备执行速查](./appendix-环境准备执行速查) | 按执行顺序快速回顾关键命令 |
