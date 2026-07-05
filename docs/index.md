---
layout: home

hero:
  name: Kubernetes 学习记录
  text: 从容器基础到核心资源
  tagline: 记录 Docker、容器运行时与 Kubernetes 的个人学习过程

features:
  - icon: 🚀
    title: 01 · 集群部署
    details: 环境规划、Ubuntu 节点准备、containerd、kubeadm、Calico、Metrics Server 和集群验证。
    link: /01-集群部署/
  - icon: 📦
    title: 02 · 容器基础
    details: 容器运行模型、Docker 架构、镜像管理、容器操作、数据持久化、容器网络、Docker Compose 和命令速查。
    link: /02-容器基础/
  - icon: 🧱
    title: 03 · 镜像制作
    details: Dockerfile、启动命令、文件复制、运行用户、镜像分层、多阶段构建、多架构镜像和 BuildKit 构建挂载。
    link: /03-镜像制作/
  - icon: 🗄️
    title: 04 · 镜像仓库
    details: 镜像仓库概念、Harbor 安装、镜像推拉、权限管理、运维管理、镜像供应链安全和漏洞扫描。
    link: /04-镜像仓库/
  - icon: 🔧
    title: 05 · 容器运行
    details: CRI、containerd、crictl、ctr、nerdctl、仓库访问配置、镜像缓存、多运行时、镜像懒加载和排障记录。
    link: /05-容器运行/
  - icon: ⚙️
    title: 06 · 集群架构
    details: Kubernetes 定位、声明式模型、集群架构、控制面组件、节点组件和核心资源抽象。
    link: /06-集群架构/
  - icon: 🧭
    title: 07 · 资源操作
    details: kubectl、Namespace、Pod 基础操作、资源状态观察和问题记录。
    link: /07-资源操作/
  - icon: 🧩
    title: 08 · Pod 入门
    details: Pod 资源定义、资源分配、环境变量、镜像拉取、生命周期、健康检查、Sidecar 容器、静态 Pod 和 Pod 调试。
    link: /08-Pod入门/
  - icon: 🧬
    title: 09 · 工作负载
    details: Deployment、StatefulSet、DaemonSet 和典型控制器行为。
    link: /09-工作负载/
  - icon: 🔎
    title: 10 · 服务发现
    details: Service、EndpointSlice、DNS、流量策略、Headless Service、代理模式、Ingress、控制器选型与 Gateway API 迁移。
    link: /10-服务发现/
---

## 当前进度

当前文档已完成基础环境、容器基础、镜像制作、镜像仓库、容器运行时，以及 Kubernetes 核心阶段的集群架构、资源操作、Pod、工作负载和服务发现。

后续记录将围绕配置管理、存储管理、任务管理、网络入口、调度治理、安全、可观测性和工程化交付逐步补齐。

## 后续补全清单

以下内容先保留为后续补全清单：

- 沙箱运行时实测：Kata Containers 与 gVisor 的节点安装、RuntimeClass 验证和沙箱内行为观察
- 镜像懒加载实测：远程 snapshotter 部署、镜像格式转换和冷启动收益验证
- Harbor 漏洞扫描实测：Trivy 扫描结果、阻止拉取策略与 CVE 允许清单的联动验证
- Gateway API 迁移实测：实现部署、ingress2gateway 转换结果验证和流量切换记录
- 网络入口与访问控制：CNI 插件选型、CoreDNS 深入、Gateway API 完整资源模型和 NetworkPolicy
- 配置管理与身份：ConfigMap、Secret、ServiceAccount、应用配置注入和镜像拉取凭据
- 存储管理：Volume、PV、PVC、StorageClass、动态供给和 VolumeSnapshot
- 任务管理：Job、CronJob 和任务型工作负载
- 调度与资源治理：nodeSelector、亲和性、污点容忍、拓扑分布、PriorityClass、抢占、驱逐、ResourceQuota、LimitRange 和 QoS
- 工作负载扩展：HPA、PDB、Workload API、PodGroupTemplates 与成组调度
- 安全与权限：RBAC、SecurityContext、Pod Security Standards 和审计基础
- 集群运维：kubeadm 配置文件、版本偏差、集群升级、证书续期、etcd 备份恢复和高可用控制平面
- 可观测性：系统日志、系统指标、事件、Tracing 和常见可观测性组件
- 交付与扩展：Helm、Operator、KEDA、GitOps、CI/CD、备份恢复和多集群管理
