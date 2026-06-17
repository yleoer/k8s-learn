# Kubernetes 学习笔记

基于 VitePress 搭建的 Kubernetes 系统学习文档站，记录 Docker、容器运行时与 Kubernetes 从基础环境到集群实践的学习过程。

## 本地开发

```bash
npm install          # 首次安装依赖
npm run docs:dev     # 启动开发服务器（http://localhost:5173）
npm run docs:build   # 构建静态站点
npm run docs:preview # 预览构建产物
```

## 课程体系（43 章 / 10 个阶段）

| 阶段 | 章节范围 | 内容 |
| --- | --- | --- |
| 一 · 入门起步 | 01 | 环境规划、Ubuntu 节点准备、containerd 组件安装、kubeadm 初始化、Calico 网络和集群验证 |
| 二 · 容器基石 | 02 ~ 05 | 容器运行模型、Docker 架构、镜像管理、镜像制作、镜像仓库和容器运行时 |
| 三 · K8s 核心资源 | 06 ~ 17 | Kubernetes 设计思想、K8s 初体验、Pod 入门与实战、Deployment 无状态调度、StatefulSet 有状态调度、Service 东西流量、Ingress 南北流量、ConfigMap/Secret 配置管理、存储管理、Job/CronJob 任务管理 |
| 四 · 综合实战 | 18 ~ 19 | SpringCloud 项目迁移至 K8s、云原生架构升级（去中心化） |
| 五 · 调度与资源治理 | 20 ~ 25 | 亲和力调度、污点与容忍、ResourceQuota、LimitRange、QoS、RBAC 权限管理 |
| 六 · 工程化与弹性 | 26 ~ 28 | Helm 包管理、Operator 扩展、KEDA 弹性伸缩 |
| 七 · 可观测性 | 29 ~ 33 | ECK 日志平台、Prometheus 监控、Alertmanager 告警、Skywalking 全链路追踪、Istio 服务网格 |
| 八 · 分布式存储 | 34 | CubeFS EB 级分布式高可用存储平台落地 |
| 九 · DevOps 落地 | 35 ~ 38 | Jenkins Pipeline、从零建设 K8s DevOps 平台、Tekton 云原生流水线 |
| 十 · 企业级落地 | 39 ~ 43 | 高可用架构设计、异地多活与智能 DNS、ArgoCD 多集群管理、集群备份恢复（Velero）、简历指导 |

## 目录结构

```
docs/
├── index.md                          # 首页（VitePress home 布局）
├── public/
│   └── favicon.svg                   # 站点图标
├── .vitepress/
│   ├── config.mjs                    # 站点配置（自动生成导航与侧边栏）
│   └── theme/
│       └── Mermaid.vue               # Mermaid 图表组件
├── 01-入门起步/                      # 章节目录（编号-标题）
│   ├── index.md                      # 章节入口（任务列表 + 目录表格）
│   ├── 1-环境规划与版本选择.md        # 课时文件（课时号-标题）
│   └── ...
├── 02-容器基础/
├── ...
└── 43-简历指导及优化/
```

### 文件命名约定

- **章节目录**：`{两位编号}-{中文标题}`，如 `10-K8s核心单元-Pod入门与实战/`
- **课时文件**：`{课时号}-{中文标题}.md`，如 `5-Pod资源分配limits和requests细节.md`
- **章节入口**：每个目录下的 `index.md`，包含章节说明、涵盖内容和目录表格
- **附录文件**：`appendix-{中文标题}.md`，会在侧边栏中显示为“附录：{中文标题}”

## 技术栈

- **[VitePress](https://vitepress.dev/)** — 静态站点生成
- **[Mermaid](https://mermaid.js.org/)** — 架构图与流程图渲染
- **自动导航生成** — 根据 `docs/` 目录结构生成顶部导航和侧边栏
