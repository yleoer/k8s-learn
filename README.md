# Kubernetes 学习记录

基于 VitePress 搭建的 Kubernetes 文档站，用于记录 Docker、容器运行时与 Kubernetes 从基础环境到集群实践的个人学习过程。

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
| 入门起步 | 01 | 环境规划、Ubuntu 节点准备、containerd 组件安装、kubeadm 初始化、Calico、Metrics Server 和集群验证 |
| 容器基础 | 02 | 容器核心概念、Docker 架构、镜像管理、容器操作、数据持久化和 Docker 命令速查 |
| 镜像制作 | 03 | Dockerfile、启动命令、文件复制、运行用户、镜像分层、多阶段构建和多架构镜像 |
| 镜像仓库 | 04 | 镜像仓库概念、Harbor 安装、镜像推拉、权限管理和运维管理 |
| 容器运行 | 05 | CRI、containerd、crictl、ctr、nerdctl、仓库访问配置和运行时排障记录 |
| Kubernetes 设计思想 | 06 | Kubernetes 定位、声明式模型、集群架构、控制面组件、节点组件和核心资源抽象 |
| Kubernetes 初体验 | 07 | kubectl、Namespace、Pod 基础操作、状态观察和问题记录 |
| Pod 入门 | 08 | Pod 资源定义、资源分配、环境变量、镜像拉取、生命周期和健康检查 |
| 工作负载 | 09 | Deployment、StatefulSet、DaemonSet、HPA 和 PDB |

## 后续补全清单

以下内容已与 Kubernetes 官方文档主线对照，当前仅作为后续记录清单保留：

- Service、EndpointSlice、CoreDNS、Ingress、Gateway API 和 NetworkPolicy
- ConfigMap、Secret、ServiceAccount 与应用配置注入
- Volume、PV、PVC、StorageClass、动态供给和 VolumeSnapshot
- Job、CronJob 与任务型工作负载
- Workload API、PodGroupTemplates 与成组调度
- nodeSelector、亲和性、污点容忍、拓扑分布、PriorityClass、抢占与驱逐
- ResourceQuota、LimitRange、QoS、RBAC、SecurityContext 和 Pod Security Standards
- 集群升级、证书、etcd 备份恢复、系统日志、系统指标和可观测性组件
- Helm、Operator、KEDA、GitOps、CI/CD、备份恢复和多集群管理

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
├── 01-入门起步/                   # 章节目录（编号-标题）
│   ├── index.md                   # 章节入口
│   ├── 1-环境规划与版本选择.md     # 文档文件（编号-标题）
│   └── ...
├── 02-容器基础/
└── 09-工作负载调度/
```

### 文件命名约定

- **章节目录**：`{两位编号}-{中文标题}`，如 `08-Pod入门/`
- **文档文件**：`{编号}-{中文标题}.md`，如 `5-Pod生命周期与优雅退出.md`
- **章节入口**：每个目录下的 `index.md`，包含章节说明、涵盖内容和目录表格
- **附录文件**：`appendix-{中文标题}.md`，会在侧边栏中显示为“附录：{中文标题}”

## 技术栈

- **[VitePress](https://vitepress.dev/)** — 静态站点生成
- **[Mermaid](https://mermaid.js.org/)** — 架构图与流程图渲染
- **自动导航生成** — 根据 `docs/` 目录结构生成顶部导航和侧边栏
