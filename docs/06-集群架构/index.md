# 集群架构

第 05 章完成了容器运行时和 CRI 的系统梳理，容器已经具备在单节点上稳定运行的基础。进入 Kubernetes 阶段后，记录重点从单节点容器运行转向多节点集群编排。

本章围绕 Kubernetes 的定位、架构、组件和核心资源展开，建立从“容器如何运行”到“集群如何编排”的整体认知。这些概念为后续记录 kubectl、Pod、Deployment、Service 等资源提供思维框架。

## 参考

- [Overview](https://kubernetes.io/docs/concepts/overview/)
- [Kubernetes Components](https://kubernetes.io/docs/concepts/overview/components/)
- [Cluster Architecture](https://kubernetes.io/docs/concepts/architecture/)
- [Leases](https://kubernetes.io/docs/concepts/architecture/leases/)
- [Objects In Kubernetes](https://kubernetes.io/docs/concepts/overview/working-with-objects/)
