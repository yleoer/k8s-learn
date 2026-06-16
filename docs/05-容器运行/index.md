# 容器运行

第 04 章已经完成镜像仓库、Harbor 权限和私有镜像拉取链路的学习。镜像进入 Kubernetes 节点后，真正负责拉取、解包和启动容器的是节点上的容器运行时。

本章将视角切换到 Kubernetes 节点内部，围绕 CRI、containerd、客户端工具、命名空间和镜像拉取排障展开。完成本章后，后续 Pod 生命周期、调度异常、镜像拉取失败和节点运行时故障排查会更加清晰。

本章涵盖以下内容：

- CRI 与 containerd 运行时体系
- ctr、crictl 与 nerdctl 客户端
- containerd 命名空间与资源隔离
- containerd 镜像仓库访问配置
- 镜像、容器与 task 管理
- 节点运行时排障与面试要点

## 目录

| 文档 | 内容 |
| --- | --- |
| [CRI 与 Containerd](./1-CRI与Containerd) | 说明 CRI 定位、dockershim 移除背景、containerd 架构和状态检查方法 |
| [客户端工具与命名空间](./2-客户端工具与命名空间) | 对比 ctr、crictl、nerdctl 的使用场景，并说明 k8s.io 命名空间 |
| [镜像仓库配置](./3-镜像仓库配置) | 配置 HTTP、自签证书 Harbor，以及 containerd hosts.toml 和认证方式 |
| [镜像容器管理](./4-镜像容器管理) | 完成镜像拉取、导入导出、打标签、推送，以及 container 和 task 排查 |
| [排障总结与面试](./5-排障总结与面试) | 汇总节点运行时常见故障路径、生产建议和高频面试问题 |
