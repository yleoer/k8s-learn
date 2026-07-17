# 扩展机制

Helm 将已有 Kubernetes API 资源打包发布；当领域对象需要专门 API 和持续控制循环时，可以通过 CustomResourceDefinition 与控制器扩展 Kubernetes。Operator 是把这种控制循环编码为软件的常见模式。

本章记录 CRD 的 API 设计、版本演进、控制器协调与运行边界。旧草稿中未指定实现与版本的 Redis、MySQL Operator 安装条目不再作为通用实践保留，实际中应按选定项目的支持矩阵、备份和故障演练另行记录。

## 共同约定

扩展 API 是长期兼容性承诺。先设计用户可见的 `spec`、可观测的 `status`、验证规则和删除语义，再编写控制器；不要将临时实现细节暴露为难以迁移的 CRD 字段。

## 参考

- [扩展 Kubernetes](https://kubernetes.io/docs/concepts/extend-kubernetes/)
- [Operator 模式](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)
