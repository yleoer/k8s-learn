# 工作负载

第 08 章已经完成 Pod 资源定义、生命周期和健康检查等基础内容，读者已经理解单个 Pod 的运行边界。本章在 Pod 基础之上引入工作负载控制器，从单实例运行进入多副本、有序身份和节点级守护进程管理阶段。

本章围绕 Deployment、StatefulSet 和 DaemonSet 展开，覆盖无状态服务、有状态应用和节点级组件的典型调度方式。这些内容将为后续 Service、Ingress、配置管理、存储和集群运维组件部署提供基础支撑。

本章涵盖以下内容：

- Deployment
- StatefulSet
- DaemonSet

## 目录

| 文档 | 内容 |
| --- | --- |
| [Deployment](./1-Deployment) | 说明无状态服务的副本维护、滚动更新、回滚和扩缩容方式 |
| [StatefulSet](./2-StatefulSet) | 讲解有状态应用的稳定身份、内部通信、扩缩容和版本管理 |
| [DaemonSet](./3-DaemonSet) | 演示节点级守护进程的创建、更新、回滚和节点选择 |

章节总结：Deployment 适合无状态业务，通过 ReplicaSet 维护副本并支持滚动更新、回滚、手动扩缩容、HPA 自动扩缩容和 PDB 中断保护。StatefulSet 适合稳定身份、有序发布和独立存储的有状态应用，DaemonSet 适合节点级常驻进程；控制器选对之后，再补充探针、资源限制、存储、配置和发布策略，才能形成稳定的生产部署。
