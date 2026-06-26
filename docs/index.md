---
layout: home

hero:
  name: Kubernetes 学习记录
  text: 从容器基础到集群实践
  tagline: 记录 Docker、容器运行时与 Kubernetes 的个人学习过程

features:
  - icon: 🚀
    title: 01 · 入门起步
    details: 环境规划、Ubuntu 节点准备、containerd、kubeadm、Calico、Metrics Server 和集群验证。
    link: /01-入门起步/
  - icon: 📦
    title: 02 · 容器基础
    details: 容器运行模型、Docker 架构、镜像管理、容器操作、数据持久化和命令速查。
    link: /02-容器基础/
  - icon: 🧱
    title: 03 · 镜像制作
    details: Dockerfile、启动命令、文件复制、运行用户、镜像分层、多阶段构建和多架构镜像。
    link: /03-镜像制作/
  - icon: 🗄️
    title: 04 · 镜像仓库
    details: 镜像仓库概念、Harbor 安装、镜像推拉、权限管理和运维管理。
    link: /04-镜像仓库/
  - icon: 🔧
    title: 05 · 容器运行
    details: CRI、containerd、crictl、ctr、nerdctl、仓库访问配置和运行时排障记录。
    link: /05-容器运行/
  - icon: ⚙️
    title: 06 · 设计思想
    details: Kubernetes 定位、声明式模型、集群架构、控制面组件、节点组件和核心资源抽象。
    link: /06-K8s设计思想/
  - icon: 🧭
    title: 07 · 初体验
    details: kubectl、Namespace、Pod 基础操作、资源状态观察和问题记录。
    link: /07-K8s初体验/
  - icon: 🧩
    title: 08 · Pod 入门
    details: Pod 资源定义、资源分配、环境变量、镜像拉取、生命周期和健康检查。
    link: /08-Pod入门/
  - icon: 🧬
    title: 09 · 工作负载
    details: Deployment、StatefulSet、DaemonSet、HPA、PDB 和典型控制器行为。
    link: /09-工作负载调度/
---

## 后续补全清单

当前文档已记录到 Pod 与三类常用工作负载。以下内容先保留为后续补全清单：

- Service、EndpointSlice、CoreDNS、Ingress、Gateway API 和 NetworkPolicy
- ConfigMap、Secret、ServiceAccount 与应用配置注入
- Volume、PV、PVC、StorageClass、动态供给和 VolumeSnapshot
- Job、CronJob 与任务型工作负载
- Workload API、PodGroupTemplates 与成组调度
- nodeSelector、亲和性、污点容忍、拓扑分布、PriorityClass、抢占与驱逐
- ResourceQuota、LimitRange、QoS、RBAC、SecurityContext 和 Pod Security Standards
- 集群升级、证书、etcd 备份恢复、系统日志、系统指标和可观测性组件
- Helm、Operator、KEDA、GitOps、CI/CD、备份恢复和多集群管理
