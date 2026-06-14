# K8s 学习记录

基于 VitePress 搭建的 Kubernetes 学习文档站。

## 本地开发

```bash
npm install        # 首次安装依赖
npm run docs:dev   # 启动本地开发服务器（默认 http://localhost:5173）
```

## 构建与预览

```bash
npm run docs:build     # 构建静态站点到 docs/.vitepress/dist
npm run docs:preview   # 本地预览构建产物
```

## 目录结构

```
docs/
├── .vitepress/
│   └── config.mjs          # 站点配置（导航、侧边栏、搜索）
├── index.md                # 首页
├── basics/                 # 基础概念
├── workloads/              # 工作负载
├── network-storage/        # 网络与存储
└── notes/                  # 实践笔记
```

## 如何新增页面

1. 在对应目录下新建 `.md` 文件
2. 在 `docs/.vitepress/config.mjs` 的 `sidebar` 中添加链接
