# Repository Guidelines

## 项目结构与模块组织

本仓库是一个基于 VitePress 的 Kubernetes 学习记录文档站点。主要内容位于 `docs/`，按章节或主题拆分目录，例如 `docs/08-Pod入门/`。每个主题目录通常包含 `index.md` 和按章节编号的 Markdown 文件，例如 `1-Pod资源定义与基础配置.md`。

站点配置、导航和构建产物位于 `docs/.vitepress/`。不要手动修改 `docs/.vitepress/dist/`，该目录由构建命令生成。根目录中的 `package.json` 定义脚本和依赖，`package-lock.json` 锁定依赖版本，`.gitignore` 排除缓存、日志和构建产物。

## 构建、测试与开发命令

- `npm install`：根据 `package-lock.json` 安装项目依赖。
- `npm run docs:dev`：启动本地开发服务，通常访问 `http://localhost:5173`。
- `npm run docs:build`：构建静态站点，输出到 `docs/.vitepress/dist/`。
- `npm run docs:preview`：本地预览生产构建结果。

提交较大的导航、Markdown、Mermaid 图或布局调整前，请至少运行 `npm run docs:build`。

## 编写风格与命名约定

文档使用 Markdown 编写。标题层级要清晰，代码块请标注语言类型，例如 `bash`、`yaml`、`mermaid`。内容应以学习记录、概念梳理和可操作示例为主，避免冗长说明。

命令输出、版本输出、示例响应等补充性内容，统一使用 VitePress `details` 容器折叠展示。标题使用“版本输出类似如下”“输出类似如下”等说明性文本，不写成已经实际执行的结果，除非确实来自本地或集群验证。格式如下：

````md
::: details 版本输出类似如下

```text
kubeadm version: &version.Info{Major:"1", Minor:"36", ..., GitVersion:"v1.36.2", ...}
Client Version: v1.36.2
Kustomize Version: v5.8.1
Kubernetes v1.36.2
crictl version v1.36.0
```

:::
````

完整 YAML、Shell、Dockerfile、TOML 等示例如果对应实际文件或建议保存为文件，应在代码块语言后添加文件名标签。文件名使用示例上下文中的真实或推荐名称，避免使用无意义的 `example.yaml`。格式如下：

````md
```yaml [deployment.yaml]
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.31-alpine
```
````

只用于介绍某一个字段或一组紧密相关配置的代码块，应使用 VitePress 行高亮突出目标配置。标量字段只高亮字段所在行；嵌套字段高亮从必要的父级入口到实际取值，避免把无关模板一并高亮。如果目标配置已经覆盖代码块的全部内容，则不添加行高亮，因为整块高亮无法形成有效对比。用于说明完整资源结构、完整配置文件或连续操作流程的代码块不为单个字段添加行高亮。例如，介绍 `spec.updateStrategy` 时，高亮 `updateStrategy:` 及其直接子配置：

````md
```yaml{8,9}
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: rolling-web
spec:
  serviceName: rolling-web
  replicas: 3
  updateStrategy:
    type: RollingUpdate
```
````

本地清单第一次提交到集群时使用 `kubectl create -f`；只有在正文已经明确说明资源存在且清单已修改时，才使用 `kubectl apply -f` 更新。命令中出现具体本地 YAML 文件名时，本页必须给出带同名文件标签的完整清单；如果复用前文已经给出的完整清单，必须提供指向原小节的明确链接并说明复用的文件名。直接引用固定版本的上游远程清单时，可以把 URL 作为完整来源，不在正文复制大体量厂商清单。

只用于解释字段关系的 YAML 可以保留为适量片段，正文必须说明它不是完整资源，并且不能为该片段提供 `kubectl create -f` 或 `kubectl apply -f` 命令。新增代码块前先搜索已有内容；正文中的相同清单、配置或命令已经出现时，优先链接到首次出现的位置，不重复粘贴代码块。以独立查阅或连续执行为目的的附录、命令速查可以重复正文中的必要代码，但内容、版本和操作语义必须与正文保持一致。

文档中的 `kubectl` 命令应优先使用 kubectl 内置短资源名。统一使用 `po`、`cm`、`deploy`、`svc`、`no`、`ns`、`ds`、`sts`、`rs`、`rc`、`cj`、`ing`、`ev`、`ep`、`pv`、`pvc`、`sc`、`sa`、`quota`、`pdb` 和 `hpa`。资源没有内置短名，或 `kubectl create` 等子命令不支持该别名时，保留可执行的完整名称。

### 示例镜像版本约束

文档中的通用示例镜像应固定到明确版本，不使用 `latest`、`stable` 或未带 tag 的镜像名作为推荐写法。当前统一使用以下版本：

| 镜像 | 固定版本 |
| --- | --- |
| Alpine | `alpine:3.23` |
| Nginx | `nginx:1.31-alpine` |
| Go | `golang:1.26-alpine` |
| BusyBox | `busybox:1.38` |
| curl | `curlimages/curl:8.21.0` |
| PHP Apache | `php:8.5.8-apache` |
| Python slim | `python:3.12-slim` |
| MySQL | `mysql:8.4` |
| PostgreSQL | `postgres:18.4` |
| Redis | `redis:8.8-alpine` |

新增示例镜像或引入新的镜像仓库地址时，必须先手动确认合适的明确版本号，再写入文档；不要凭记忆沿用旧标签。若示例用于说明默认 tag、升级、回滚、灰度或分段发布，可以使用其他明确版本，但正文需要说明该版本差异服务于示例语义。

提示、建议、风险和注意事项统一使用 GitHub 风格警报，不使用 VitePress 专属的 `::: warning`、`::: tip` 等容器。按语义选择以下格式：

```md
> [!NOTE]
> 强调用户在快速浏览文档时也不应忽略的重要信息。

> [!TIP]
> 有助于用户更顺利达成目标的建议性信息。

> [!IMPORTANT]
> 对用户达成目标至关重要的信息。

> [!WARNING]
> 因为可能存在风险，所以需要用户立即关注的关键内容。

> [!CAUTION]
> 行为可能带来的负面影响。
```

### 文档定位与内容边界

本项目是个人学习记录，不是教程、课程或培训材料。正文不要加入“学习目标”“前置知识”“适合读者”“课程安排”“面试题”等教学化结构，也不要使用“掌握”“熟悉”“了解”“初学者”等教程式表达。项目标题、首页说明中可以保留“学习记录”“个人学习过程”等定位性表述。

概念描述应简洁、准确、完整。解释 Kubernetes、Pod、CRI、CNI、CSI、Deployment、StatefulSet、DaemonSet、Service、Metrics Server 等概念时，优先对齐当前 Kubernetes 官方文档的定义和边界；信息可能随版本变化时，应先查阅官方文档再修改。

新增或调整 Kubernetes YAML、Dockerfile、Shell 示例时，应尽量提供完整可运行片段，避免只给孤立字段。确实只展示局部字段时，需要在正文中说明该片段用于解释字段关系，不应伪装成完整资源。

发现当前文档缺失的主题时，不要在无充分内容准备的情况下临时扩写章节。先记录到 `README.md` 和 `docs/index.md` 的后续补充清单，等待后续逐步完善。

### Kubernetes 文档审校与完善规范

当用户要求检查、完善或扩写 Kubernetes 相关文档时，必须先按最新官方文档核验事实，再修改正文。官方来源优先级为：当前英文版 Kubernetes 官方文档、当前 Kubernetes API Reference、kubectl 官方参考、相关功能的官方任务页或概念页；中文官方文档可以辅助理解和用词，但不得作为唯一事实依据。每次涉及版本、弃用、移除、默认行为、API 字段、特性门控或命令语义时，都要重新查阅官方页面，不沿用记忆中的旧版本结论。

审校时按以下维度逐项检查：

- 内容完整性：核对章节是否覆盖当前主题必要的定义、适用场景、资源边界、关键字段、默认行为、生命周期或状态、与相邻概念的区别、常见限制和后续关联主题；缺失但暂时无法充分展开的内容，记录到后续补充清单，不临时堆砌段落。
- 事实准确性：核对 API 组、`apiVersion`、字段名称、字段层级、默认值、控制器行为、网络和存储边界、命令参数、输出含义是否与当前官方文档一致；对不确定或版本相关的表述，改为带条件的准确表达。
- 过时信息：重点排查已弃用或已移除的 API、旧版命令写法、历史组件行为和过时术语，例如将 dockershim、PodSecurityPolicy、`extensions/v1beta1`、`apps/v1beta1` 等内容仅作为历史背景处理，不能作为当前推荐用法。
- 概念边界：解释 Pod、Deployment、StatefulSet、DaemonSet、Service、Ingress、Gateway API、ConfigMap、Secret、Volume、PV、PVC、StorageClass、CRI、CNI、CSI、Metrics Server 等概念时，要说明其在 Kubernetes 中解决的问题和不负责的范围，避免把相关但不同层级的概念混为一谈。
- 示例完整性：YAML、Dockerfile、Shell 命令应尽量提供可直接运行的完整片段；如果只展示局部字段，必须明确说明该片段用于解释字段关系，不能伪装成完整资源。
- 示例正确性：检查 YAML 缩进、资源层级、标签选择器匹配关系、端口名称和端口号、镜像名称、命名空间、Secret 或 ConfigMap 引用、Service 与 Pod 标签、PVC 与 StorageClass、探针路径和端口等是否自洽。
- 官方示例复用：通用示例优先参考 Kubernetes 官方任务页、概念页和 `https://k8s.io/examples/` 中的示例；可以根据本仓库上下文调整名称和说明，但不得改坏字段语义。正文直接使用示例，不反复写“官方示例”“来自官方文档”等来源说明。若官方示例依赖云厂商、特定插件或特定集群能力，需要在正文中说明适用条件。
- 多余示例处理：删除无法解释主题、字段错误、版本过时、与正文不一致或容易误导的示例。确需保留反例时，必须明确标注为反例，并紧邻给出正确写法或风险说明。
- 执行结果：命令输出只能使用实际验证结果或官方文档中的示例输出。未在本地或集群中执行过的命令，不得写成“执行后得到如下结果”；可以写为“输出类似如下”或仅说明预期现象。
- 术语与语气：正文保持书面中文，避免口语化、营销化和教学化表达。API Kind 使用官方大小写，例如 Pod、Service、Deployment、StatefulSet；字段名、命令、参数和资源路径使用行内代码格式；避免“Node 节点”“Pod 容器”等中英文重复或概念混淆表达。
- 来源记录：完成较大事实修订时，在回复中列出参考过的官方页面链接；正文不需要堆叠引用，但涉及版本差异、弃用状态或外部组件边界时，应在文中保留必要的官方入口链接。文档内如需集中列出来源，二级标题统一使用 `## 参考`。

概念页和操作页的写法要区分。概念梳理以“是什么、解决什么问题、与哪些对象协作、边界是什么”为主，不写成连续操作教程；操作记录可以包含步骤、命令和结果，但每个步骤应服务于一个明确的验证目标，避免把官方教程整段搬运到个人笔记中。

### index.md 写作规范

各章节 `index.md` 文件用于章节入口说明和章节共有背景整理，必须保持全书风格统一、结构清晰、表述书面。

一级标题使用不超过 6 个汉字的名词短语，不加序号、标点或副标题，例如 `# 容器基础`、`# 镜像仓库`、`# 容器运行`。

标题下方优先写两段承上启下内容，不得合并为一段。第一段点明本章与上一章的衔接关系，说明当前阶段的起点或前置背景，用一到两句话完成，不展开细节。第二段概述本章覆盖范围与记录脉络，并说明本章内容对后续章节的支撑作用，同样控制在两句话以内。

`index.md` 可以承载章节级背景和多篇文档共用的内容，包括：

- 本章主题的统一边界、问题域和与前后章节的关系
- 多篇文档共同依赖的基础概念、术语和对象关系
- 跨资源通用的 Label、Selector、命名、访问边界等背景
- 官方示例中需要作为章节公共上下文保留的 YAML、Shell 或文本片段
- 本章参考的官方文档、API Reference、kubectl 参考和官方 examples 链接

`index.md` 不包含 `本章涵盖以下内容` 列表，也不包含 `## 目录` 表格。

`index.md` 禁止事项：

- 不在引言段落中使用“本节”，统一使用“本章”。
- 不加入“学习目标”“前置知识”“适合读者”“课程安排”“面试题”等教学化结构。
- 不用“掌握”“熟悉”“了解”“学习”等教程式表达描述读者任务。
- 不把某一篇专题文档的完整正文搬到 `index.md`，专题细节仍应放入对应编号文档。
- 不为了凑结构添加重复侧边栏、重复目录或无信息量列表。
- 不放置未经官方文档或实际验证支撑的 YAML、Shell、Dockerfile 或命令输出。
- 标题、引言、正文块、列表、表格之间各空一行，不添加多余空行。

语言风格要求：全程使用书面中文，避免口语化表达；专有名词（Docker、Kubernetes、Pod、CRI、CNI 等）保留英文原文；中英文之间加空格，标点使用中文全角符号；避免使用“首先”“其次”“然后”等顺序副词。

新增文件时沿用现有命名方式：章节号、文档序号、中文标题和 `.md` 后缀，例如 `3-DaemonSet.md`。修改 VitePress 配置时使用标准 JavaScript 模块语法和两个空格缩进。不要提交 `node_modules/`、日志、缓存或构建产物。

## 测试与校验指南

本仓库暂无独立自动化测试套件，校验重点是文档站点是否能正常构建和浏览：

- 使用 `npm run docs:build` 检查构建是否成功。
- 修改导航、链接、图片、Mermaid 图或页面结构后，用 `npm run docs:preview` 预览。
- 检查新增内部链接、图片路径和章节入口是否可访问。
- Kubernetes YAML 示例应保持缩进一致，并尽量保证语法完整、字段合理。

## 提交规范

提交信息使用简短中文摘要，例如 `初始化学习文档项目`、`补充镜像仓库章节笔记`。每次提交应聚焦一个章节、主题或明确修复点。

提交描述中使用简短中文列表列出每一项改动，例如：

```md
- 调整 01 集群部署目录结构
- 补充 containerd 镜像加速说明
- 更新 VitePress 字体配置
```

## 安全与配置提示

不要提交 kubeconfig、Token、私有镜像仓库凭据、云厂商密钥或真实生产主机名。示例中使用 `<registry.example.com>`、`<namespace>` 等占位符。敏感配置应保存在仓库外的本地环境文件中。
