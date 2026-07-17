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
    details: Dockerfile、构建上下文、基础镜像、镜像元数据、文件复制、运行用户、启动命令、变量配置、镜像分层、多阶段构建、BuildKit 构建挂载和多架构镜像。
    link: /03-镜像制作/
  - icon: 🗄️
    title: 04 · 镜像仓库
    details: 镜像仓库概念、Harbor 安装、镜像推拉、权限管理、运维管理、镜像供应链安全和漏洞扫描。
    link: /04-镜像仓库/
  - icon: 🔧
    title: 05 · 容器运行
    details: CRI、containerd、crictl、ctr、nerdctl、仓库访问配置和运行时排障记录。
    link: /05-容器运行/
  - icon: ⚙️
    title: 06 · 集群架构
    details: Kubernetes 定位、声明式模型、集群架构、控制面组件、节点组件和核心资源抽象。
    link: /06-集群架构/
  - icon: 🧭
    title: 07 · 资源操作
    details: kubectl、Namespace、Pod 基础操作、资源状态观察和命令速查。
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
    details: Service、EndpointSlice、DNS、流量策略、Headless Service、代理模式、Ingress、Gateway API、Traefik 和 ingress-nginx 附录。
    link: /10-服务发现/
  - icon: 🧾
    title: 11 · 配置管理
    details: ConfigMap、Secret、配置注入、更新传播、不可变配置、镜像仓库凭据和 Secret 安全边界。
    link: /11-配置管理/
  - icon: 💾
    title: 12 · 存储管理
    details: Volume、PV、PVC、StorageClass、CSI、NFS 动态供给、扩容、快照边界和存储排障。
    link: /12-存储管理/
  - icon: ⏱️
    title: 13 · 任务管理
    details: Job、Indexed Job、失败与成功策略、TTL、CronJob 调度、并发策略和 MySQL 定时备份。
    link: /13-任务管理/
  - icon: 🧭
    title: 14 · 调度策略
    details: 节点选择、亲和性、拓扑分布、PriorityClass、PDB 和调度排障。
    link: /14-调度策略/
  - icon: 🚧
    title: 15 · 污点容忍
    details: 污点效果、容忍匹配、专用节点隔离、节点维护和排障。
    link: /15-污点容忍/
  - icon: 📊
    title: 16 · 资源配额
    details: ResourceQuota、计算与存储配额、范围和命名空间治理。
    link: /16-资源配额/
  - icon: 📏
    title: 17 · 限制范围
    details: LimitRange、容器默认资源、PVC 范围及其与配额的配合。
    link: /17-限制范围/
  - icon: ⚖️
    title: 18 · 服务质量
    details: QoS 类别、资源配置、节点驱逐、OOM 与资源压力排障。
    link: /18-服务质量/
  - icon: 🔐
    title: 19 · RBAC
    details: 身份认证边界、ServiceAccount、最小权限、授权验证与 kubeconfig。
    link: /19-RBAC/
  - icon: ⎈
    title: 20 · Helm
    details: Helm 4、Chart 模板、OCI 仓库、依赖、发布、回滚与安全边界。
    link: /20-Helm/
  - icon: 🧩
    title: 21 · 扩展机制
    details: CRD、模式验证、版本演进、控制器协调和 Operator 模式。
    link: /21-扩展机制/
---

## 当前进度

当前文档已完成基础环境、容器基础、镜像制作、镜像仓库、容器运行时，以及 Kubernetes 核心阶段的集群架构、资源操作、Pod、工作负载、服务发现、配置管理、存储管理和任务管理；调度治理、资源约束、RBAC、Helm 与扩展 API 也已形成独立记录。

后续记录从第 22 章 Operator 开始，随后依次补充可观测性、分布式存储、DevOps 和企业级落地相关主题。

## 后续补全清单

以下内容先保留为后续补全清单：

- 节点镜像缓存与垃圾回收：节点镜像缓存边界、kubelet 镜像垃圾回收策略与磁盘压力排查
- RuntimeClass 与多运行时：containerd 运行时处理器配置、RuntimeClass 调度与开销，以及 Kata Containers 和 gVisor 验证
- Snapshotter 与镜像懒加载：snapshotter 选型、远程 snapshotter 部署、镜像格式转换和冷启动收益验证
- Harbor 漏洞扫描实测：Trivy 扫描结果、阻止拉取策略与 CVE 允许清单的联动验证
- Harbor 生产部署：高可用拓扑、外部 PostgreSQL 与 Redis、对象存储、备份恢复和跨版本升级演练
- Docker 运行治理：CPU、内存、PID 与 ulimit 约束，rootless 与 user namespace，capabilities、seccomp 和日志驱动
- 镜像构建进阶：`STOPSIGNAL`、`SHELL`、`VOLUME`、`ONBUILD`，Build checks、远程缓存、可复现构建和构建器垃圾回收
- Gateway API 迁移实测：实现部署、ingress2gateway 转换结果验证和流量切换记录
- 网络入口与访问控制：CNI 插件选型、CoreDNS 深入、Gateway API 完整资源模型和 NetworkPolicy
- 身份管理：ServiceAccount、短期令牌投射、工作负载身份和镜像拉取凭据复用
- 存储实测补充：CSI VolumeSnapshot 控制器部署、快照恢复、卷克隆、应用一致性和故障恢复演练
- 任务管理实测补充：大规模 Indexed Job、外部工作队列、失败策略观测和备份恢复演练
- Pod 新能力：Pod 级资源配置、运行中资源调整、容器级重启规则、`PodReadyToStartContainers`、用户命名空间和细粒度补充组策略
- 工作负载扩展：HPA、PDB、Workload API、PodGroupTemplates 与成组调度
- 工作负载状态与发布：Deployment `terminatingReplicas`、滚动发布容量峰值、StatefulSet 强制回滚边界，以及工作负载终止与 Service 终止端点的连接排空协同
- Service 网络进阶：ServiceCIDR 与 IPAddress、多 CIDR 分配、拓扑感知路由、终止端点流量排空、NodeLocal DNSCache 和 CoreDNS 定制
- 安全深化：SecurityContext、Pod Security Standards、审计基础和工作负载身份
- 集群运维：kubeadm 配置文件、版本偏差、集群升级、证书续期、etcd 备份恢复和高可用控制平面
- 可观测性：系统日志、系统指标、事件、Tracing 和常见可观测性组件
- Operator：API 与状态设计、协调循环、Kubebuilder 与 controller-runtime、Webhook、RBAC、测试、发布升级，以及具体 Operator 的运行与排障
- 交付与扩展深化：KEDA、GitOps、CI/CD、备份恢复和多集群管理
