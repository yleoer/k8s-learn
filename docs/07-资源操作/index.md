# 资源操作

第 06 章已经梳理了 Kubernetes 的定位、集群架构和核心资源抽象。本章从集群架构转入资源操作记录，观察资源如何被创建、存储、调度和运行。

本章围绕 kubectl、Namespace 和最小 Pod 观察展开：先建立与集群交互的基本方法，再完成资源的查看、创建、修改、删除和基础状态排查。Pod 在本章只作为资源操作入口出现，具体 spec 字段、生命周期、资源配置和探针细节放在第 08 章继续记录。

## 参考

- [Command line tool (kubectl)](https://kubernetes.io/docs/reference/kubectl/)
- [Namespaces](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/)
- [Share a Cluster with Namespaces](https://kubernetes.io/docs/tasks/administer-cluster/namespaces/)
- [Pods](https://kubernetes.io/docs/concepts/workloads/pods/)
- [Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
- [Debug Running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/)
