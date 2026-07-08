# Kubernetes 学习记录

基于 VitePress 搭建的 Kubernetes 文档站，用于记录 Docker、容器运行时与 Kubernetes 从基础环境到集群实践的个人学习过程。

当前已完成 01-10 章，其中 06-10 章对应 Kubernetes 核心资源阶段：集群架构、资源操作、Pod、工作负载和服务发现。

## 本地开发

```bash
npm install          # 首次安装依赖
npm run docs:dev     # 启动开发服务器（http://localhost:5173）
npm run docs:build   # 构建静态站点
npm run docs:preview # 预览构建产物
```

## 当前记录范围

| 范围 | 章节 | 内容 |
| --- | --- | --- |
| 集群部署 | 01 | 环境规划、Ubuntu 节点准备、containerd 组件安装、kubeadm 初始化、Calico、Metrics Server 和集群验证 |
| 容器基础 | 02 | 容器核心概念、Docker 架构、镜像管理、容器操作、数据持久化、容器网络、Docker Compose 和 Docker 命令速查 |
| 镜像制作 | 03 | Dockerfile、构建上下文、基础镜像、镜像元数据、文件复制、运行用户、启动命令、变量配置、镜像分层、多阶段构建、BuildKit 构建挂载和多架构镜像 |
| 镜像仓库 | 04 | 镜像仓库概念、Harbor 安装、镜像推拉、权限管理、运维管理、镜像供应链安全和漏洞扫描 |
| 容器运行 | 05 | CRI、containerd、crictl、ctr、nerdctl、仓库访问配置、镜像缓存、RuntimeClass 多运行时、镜像懒加载和运行时排障记录 |
| 集群架构 | 06 | Kubernetes 定位、声明式模型、集群架构、控制面组件、节点组件和核心资源抽象 |
| 资源操作 | 07 | kubectl、Namespace、Pod 基础操作、状态观察和问题记录 |
| Pod 入门 | 08 | Pod 资源定义、资源分配、环境变量、镜像拉取、生命周期、健康检查、Sidecar 容器、静态 Pod 和 Pod 调试 |
| 工作负载 | 09 | Deployment、StatefulSet、DaemonSet 和典型控制器行为 |
| 服务发现 | 10 | Service、EndpointSlice、DNS、Service 类型、流量策略、Headless Service、代理模式、Ingress、Gateway API、Traefik 和 ingress-nginx 附录 |

## 后续补全清单

以下内容已与 Kubernetes 官方文档主线对照，当前仅作为后续记录清单保留：

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

## 目录结构

```
docs/
├── index.md                       # 首页（VitePress home 布局）
├── public/
│   └── favicon.svg                # 站点图标
├── .vitepress/
│   ├── config.mjs                 # 站点配置（自动生成导航与侧边栏）
│   └── theme/
│       └── Mermaid.vue            # Mermaid 图表组件
├── 01-集群部署/                   # 章节目录（编号-标题）
│   ├── index.md                   # 章节入口
│   ├── 1-环境规划与基础准备.md
│   └── ...
├── 02-容器基础/
├── 03-镜像制作/
├── 04-镜像仓库/
├── 05-容器运行/
├── 06-集群架构/
├── 07-资源操作/
├── 08-Pod入门/
├── 09-工作负载/
└── 10-服务发现/
```

### 文件命名约定

- **章节目录**：`{两位编号}-{中文标题}`，如 `08-Pod入门/`
- **文档文件**：`{编号}-{中文标题}.md`，如 `5-Pod生命周期与优雅退出.md`
- **章节入口**：每个目录下的 `index.md`，包含章节入口说明和章节共有背景
- **附录文件**：`appendix-{中文标题}.md`，会在侧边栏中显示为“附录：{中文标题}”

## 技术栈

- **[VitePress](https://vitepress.dev/)** — 静态站点生成
- **[Mermaid](https://mermaid.js.org/)** — 架构图与流程图渲染
- **自动导航生成** — 根据 `docs/` 目录结构生成顶部导航和侧边栏
