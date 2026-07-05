# Kubernetes 文档缺失内容补充

你正在维护一个 VitePress Kubernetes 学习记录文档站。请先阅读仓库根目录的 `AGENTS.md`，并严格遵守其中所有写作、命名、示例、告警块、details 容器、`index.md` 和 Kubernetes 文档审校规范。

## 工作目标

请检查并补充当前 `docs/` 中已经存在的相关章节内容，重点补齐以下主题。补充时不要把本文当成唯一事实来源；涉及 Kubernetes、Docker、containerd、Harbor、ingress-nginx、Gateway API、特性状态、版本变化、弃用或退役信息时，必须先查阅当前官方文档或项目官方公告，再修改正文。

## 补充范围

### 容器基础

目标章节优先放在 `docs/02-容器基础/`，必要时可关联 `docs/05-容器运行/`：

- Docker 网络模型：`bridge`、`host`、`none`
- 容器间通信
- Docker Compose 基础

### 镜像制作

目标章节优先放在 `docs/03-镜像制作/`：

- BuildKit 缓存挂载与 secret 挂载：`RUN --mount`
- Dockerfile heredoc 写法

### 镜像仓库

目标章节优先放在 `docs/04-镜像仓库/`：

- Harbor 漏洞扫描，重点核验 Trivy 集成与扫描策略
- CVE 允许清单
- 不可变标签

### 容器运行

目标章节优先放在 `docs/05-容器运行/`：

- RuntimeClass 与多运行时
- Kata Containers
- gVisor
- containerd snapshotter 选型
- 镜像懒加载

### Pod 入门

目标章节优先放在 `docs/08-Pod入门/`：

- 原生 Sidecar 容器，即 `restartPolicy: Always` 的 Init Container
- 静态 Pod
- 临时容器与 `kubectl debug`
- `downwardAPI` 卷
- `resourceFieldRef`

### 工作负载

目标章节优先放在 `docs/09-工作负载/`：

- StatefulSet `spec.ordinals` 起始序号
- StatefulSet 滚动更新 `maxUnavailable`，需核验 v1.35 beta 状态和当前版本状态
- StatefulSet 的 `minReadySeconds`
- DaemonSet 的 `minReadySeconds`

### 服务发现

目标章节优先放在 `docs/10-服务发现/`：

- ingress-nginx 退役信息，需核验 2026 年 3 月相关官方公告或项目维护状态
- Ingress Controller 选型
- Gateway API 迁移

## 写作要求

1. 先审阅对应章节现有内容，判断每个主题适合补到已有文件、章节 `index.md`，还是需要新增编号 Markdown 文件。新增文件必须沿用仓库命名方式，例如 `6-主题名称.md`。
2. 不要加入“学习目标”“前置知识”“适合读者”“课程安排”“面试题”等教学化结构，不使用“掌握”“熟悉”“了解”“初学者”等教程式表达。
3. 概念页以“是什么、解决什么问题、与哪些对象协作、边界是什么”为主；操作记录可以包含步骤、命令和结果，但每个步骤必须服务于明确的验证目标。
4. 新增 YAML、Dockerfile、Shell 示例时，尽量给出完整可运行片段，并按 `AGENTS.md` 要求给代码块添加语言和文件名标签。
5. 未实际执行过的命令输出，不得写成“执行后得到如下结果”；可使用 `::: details 输出类似如下` 或只说明预期现象。
6. 提示、建议、风险和注意事项必须使用 GitHub 风格警报，不使用 VitePress 专属 `::: warning`、`::: tip` 等容器。
7. 对暂时无法充分展开或需要后续实测的内容，不要临时堆砌正文，应记录到 `README.md` 和 `docs/index.md` 的后续补充清单。
8. 修改 VitePress 导航或侧边栏时，保持现有 JavaScript 模块风格和两个空格缩进。
9. 不要修改 `docs/.vitepress/dist/`、`node_modules/`、`.claude/`、日志、缓存或与本任务无关的章节。

## 官方资料要求

请优先查阅并使用以下类型的来源：

- 当前英文版 Kubernetes 官方文档
- Kubernetes API Reference
- kubectl 官方参考
- Kubernetes 官方任务页或概念页
- `https://k8s.io/examples/`
- Docker 官方文档
- Docker BuildKit 官方文档
- Harbor 官方文档
- containerd、Kata Containers、gVisor、Gateway API、ingress-nginx 项目官方文档或公告

正文不需要堆叠引用，但涉及版本差异、弃用状态、退役信息、外部组件边界或迁移建议时，应在文中保留必要官方入口链接。完成后在回复中列出参考过的官方页面链接。

## 完成标准

完成这些缺失内容的补充，并在最后简要报告：

- 修改或新增了哪些文件
- 每个补充主题落到了哪个章节或文件
- 删除或更正了哪些过时、错误、重复或误导性内容
- 哪些内容仍需后续实测或继续补充
- 本次参考过的官方页面链接
