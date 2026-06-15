# Repository Guidelines

## 项目结构与模块组织

本仓库是一个基于 VitePress 的 Kubernetes 学习文档站点。主要内容位于 `docs/`，按章节或主题拆分目录，例如 `docs/10-K8s核心单元-Pod入门与实战/`。每个主题目录通常包含 `index.md` 和按课时编号的 Markdown 文件，例如 `10-1-...md`。

站点配置、导航和构建产物位于 `docs/.vitepress/`。不要手动修改 `docs/.vitepress/dist/`，该目录由构建命令生成。根目录中的 `package.json` 定义脚本和依赖，`package-lock.json` 锁定依赖版本，`.gitignore` 排除缓存、日志和构建产物。

## 构建、测试与开发命令

- `npm install`：根据 `package-lock.json` 安装项目依赖。
- `npm run docs:dev`：启动本地开发服务，通常访问 `http://localhost:5173`。
- `npm run docs:build`：构建静态站点，输出到 `docs/.vitepress/dist/`。
- `npm run docs:preview`：本地预览生产构建结果。

提交较大的导航、Markdown、Mermaid 图或布局调整前，请至少运行 `npm run docs:build`。

## 编写风格与命名约定

文档使用 Markdown 编写。标题层级要清晰，代码块请标注语言类型，例如 `bash`、`yaml`、`mermaid`。内容应以可操作示例为主，避免冗长说明。

每个主题目录的 `index.md` 应统一使用章节入口格式：

- 一级标题使用章节名称，例如 `# 容器基础`。
- 标题下先写一段阶段介绍，说明本阶段学习范围、练习目标，以及与后续 Kubernetes 内容的关系。
- 阶段介绍后使用“本阶段的任务是：”引出任务列表，任务列表使用 `-`，每项描述一个明确学习目标或操作能力。
- 目录标题统一使用 `## 目录`。
- 目录使用两列表格，表头为 `文档` 和 `内容`；左列放章节链接，链接文本不带课时编号，右列用一句话说明该文档覆盖的重点。
- 章节链接使用相对路径，例如 `[Docker 镜像管理](./8-Docker镜像管理)`。

新增文件时沿用现有命名方式：章节号、课时号、中文标题和 `.md` 后缀，例如 `21-10-污点增删改查-修改污点.md`。修改 VitePress 配置时使用标准 JavaScript 模块语法和两个空格缩进。不要提交 `node_modules/`、日志、缓存或构建产物。

## 测试与校验指南

本仓库暂无独立自动化测试套件，校验重点是文档站点是否能正常构建和浏览：

- 使用 `npm run docs:build` 检查构建是否成功。
- 修改导航、链接、图片、Mermaid 图或页面结构后，用 `npm run docs:preview` 预览。
- 检查新增内部链接、图片路径和章节入口是否可访问。
- Kubernetes YAML 示例应保持缩进一致，并尽量保证语法合理。

## 提交与 Pull Request 规范

提交信息使用简短中文摘要，例如 `初始化学习文档项目`、`补充镜像仓库章节笔记`。每次提交应聚焦一个章节、主题或明确修复点。

提交或 Pull Request 描述中使用简短中文列表列出每一项改动，例如：

```md
- 调整 01 入门起步目录结构
- 补充 containerd 镜像加速说明
- 更新 VitePress 字体配置
```

Pull Request 还应包含涉及的章节路径、已执行的校验命令。涉及页面展示、导航或图表变化时，请附截图或说明预览结果。如有关联 issue 或学习任务，请在描述中链接。

## 安全与配置提示

不要提交 kubeconfig、Token、私有镜像仓库凭据、云厂商密钥或真实生产主机名。示例中使用 `<registry.example.com>`、`<namespace>` 等占位符。敏感配置应保存在仓库外的本地环境文件中。
