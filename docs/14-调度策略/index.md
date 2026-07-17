# 调度策略

工作负载控制器定义副本数和更新方式后，调度器还需要在满足资源、策略和约束的节点中选择落点。前面的 Pod、工作负载与存储配置构成调度的输入，本章将其收敛为可审查的放置规则。

本章记录节点选择、亲和性、反亲和性和拓扑分布的边界，以及高可用工作负载的组合方式。污点与容忍、资源配额和驱逐策略随后分别处理节点准入、命名空间治理和资源压力。

## 共同约定

调度规则依赖节点标签和工作负载标签。节点的位置、机型、磁盘类型等属性应由受控自动化写入；应用不得依赖临时手工标签。`topology.kubernetes.io/zone` 与 `kubernetes.io/hostname` 是 Kubernetes 定义的稳定拓扑标签，其他拓扑键应统一前缀和取值字典。

`requiredDuringSchedulingIgnoredDuringExecution` 只在调度时强制检查。节点标签变化后，已有 Pod 不会因该字段自动迁移；对运行期间的合规性要求，需要结合节点治理、重新部署或专门控制器处理。

## 参考

- [将 Pod 分配到节点](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/)
- [Pod 拓扑分布约束](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/)
