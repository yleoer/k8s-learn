# 无状态调度

第 08 章已经完成 Pod 资源定义、生命周期和健康检查等基础内容，读者已经理解单个 Pod 的运行边界。本章在第 08 章的基础之上引入控制器能力，从单实例运行进入多副本、可更新、可回滚的应用管理阶段。

本章围绕 ReplicaSet、ReplicationController 和 Deployment 展开，覆盖无状态服务的创建、更新、回滚、扩缩容和更新策略。这些内容将为后续 Service、Ingress、ConfigMap、Secret 和存储章节中的应用发布提供基础支撑。

本章涵盖以下内容：

- 无状态调度基础
- Deployment 定义与创建
- Deployment 更新与回滚
- Deployment 扩缩容与策略

## 目录

| 文档 | 内容 |
| --- | --- |
| [无状态调度基础](./1-无状态调度基础) | 说明无状态服务、RC、ReplicaSet 和 Deployment 的关系 |
| [Deployment 定义与创建](./2-Deployment定义与创建) | 拆解 Deployment 资源字段，观察 Deployment 创建 Pod 的完整链路 |
| [Deployment 更新与回滚](./3-Deployment更新与回滚) | 演示镜像更新、版本回滚、暂停恢复和历史版本保留 |
| [Deployment 扩缩容与策略](./4-Deployment扩缩容与策略) | 讲解副本调整、RollingUpdate、Recreate 和滚动发布注意事项 |
