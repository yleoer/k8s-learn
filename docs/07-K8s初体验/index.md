# 初体验

第 06 章已经梳理了 Kubernetes 的设计思想、集群架构和核心资源抽象。本章从集群架构转入资源操作记录，观察资源如何被创建、存储、调度和运行。

本章围绕 kubectl、Namespace 和 Pod 展开：先建立与集群交互的基本方法，再完成资源的查看、创建、修改、删除和排障等入门实践。这些基础操作将支撑后续 Deployment、Service、ConfigMap 等核心资源章节记录。

本章涵盖以下内容：

- Kubernetes 初体验路径
- kubectl 命令格式
- 资源增删改查
- kubectl 常用操作
- Namespace 基本使用
- Pod 概念与架构
- Pod 设计思想
- Pod 基本使用
- Pod 状态排查
- 初体验问题记录

## 目录

| 文档 | 内容 |
| --- | --- |
| [K8s 初体验章节内容介绍](./1-K8s初体验章节内容介绍) | 建立 Kubernetes 操作入口、交互链路和本章实践主线 |
| [Kubectl 命令格式详解](./2-Kubectl命令格式详解) | 说明 kubectl 基本语法、资源类型、名称和常用标志 |
| [Kubectl 增删改查命令详解](./3-Kubectl增删改查命令详解) | 使用 create、apply、get、edit、replace、delete 操作资源 |
| [Kubectl 常用命令详解](./4-Kubectl常用命令详解) | 集中梳理上下文、资源查看、日志、调试、文件传输和 explain 等命令 |
| [Namespace 基本使用](./5-Namespace基本使用) | 说明 Namespace 概念、默认空间、创建删除、切换和资源归属 |
| [Pod 概念及 Pod 架构](./6-Pod概念及Pod架构) | 说明 Pod 与容器的关系、共享资源和基础架构 |
| [Pod 设计思想及解决的问题](./7-Pod设计思想及解决的问题) | 分析为什么 Kubernetes 以 Pod 作为调度基本对象 |
| [Pod 基本使用及多容器注意事项](./8-Pod基本使用及多容器注意事项) | 通过 YAML 创建 Pod，并说明多容器 Pod 的常见约束 |
| [Pod 常见状态及问题排查通用方法](./9-Pod常见状态及问题排查通用方法) | 梳理 Pending、Running、CrashLoopBackOff 等状态的排查路径 |
| [K8s 初体验问题记录](./10-K8s初体验问题记录) | 记录本章核心命令、资源关系和常见问题 |
