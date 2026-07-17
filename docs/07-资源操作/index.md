# 资源操作

第 06 章已经梳理了 Kubernetes 的定位、集群架构和资源对象关系。本章从架构视角转入资源操作，观察对象如何被提交、查询、更新和删除。

本章围绕 kubectl、Namespace 和最小 Pod 观察展开，建立清单管理、资源查询和基础状态排查的共同入口。Pod 在本章只作为资源操作对象出现，具体对象结构、生命周期、资源配置和探针细节放在第 08 章继续记录。

## 参考

- [kubectl 命令行工具](https://kubernetes.io/docs/reference/kubectl/)
- [命名空间](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/)
- [使用命名空间共享集群](https://kubernetes.io/docs/tasks/administer-cluster/namespaces/)
- [Pod](https://kubernetes.io/docs/concepts/workloads/pods/)
- [Pod 生命周期](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
- [调试运行中的 Pod](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/)
- [使用配置文件管理 Kubernetes 对象](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/)
- [使用 kubeconfig 文件组织集群访问](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)
- [标签与选择器](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)
