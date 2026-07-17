# 服务质量

在资源压力下，Kubernetes 需要区分不同资源声明的 Pod。QoS 类别从每个容器的 CPU 与内存 requests、limits 自动计算，不是可直接写入的 Pod 字段。

本章记录 `Guaranteed`、`Burstable`、`BestEffort` 的判定及其与驱逐的关系。QoS 不是服务重要性的完整表达，还应结合 PriorityClass、PDB、容量与应用恢复能力。

## 参考

- [Pod 服务质量类别](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/)
- [节点压力驱逐](https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/)
