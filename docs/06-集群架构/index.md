# 集群架构

第 05 章完成了容器运行时和 CRI 的系统梳理，容器已经具备在单节点上稳定运行的基础。进入 Kubernetes 阶段后，记录重点从单节点容器运行转向多节点集群编排。

本章围绕 Kubernetes 的定位、架构、组件和资源对象关系展开，建立从“容器如何运行”到“集群如何编排”的整体认知。这些概念为后续记录 kubectl、Pod、Deployment、Service 等资源提供思维框架。

## 参考

- [概览](https://kubernetes.io/docs/concepts/overview/)
- [Kubernetes 组件](https://kubernetes.io/docs/concepts/overview/components/)
- [集群架构](https://kubernetes.io/docs/concepts/architecture/)
- [Lease](https://kubernetes.io/docs/concepts/architecture/leases/)
- [Kubernetes 中的对象](https://kubernetes.io/docs/concepts/overview/working-with-objects/)
- [集群网络](https://kubernetes.io/docs/concepts/cluster-administration/networking/)
- [虚拟 IP 与 Service 代理](https://kubernetes.io/docs/reference/networking/virtual-ips/)
- [Service 与 Pod 的 DNS](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [资源指标管道](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)
