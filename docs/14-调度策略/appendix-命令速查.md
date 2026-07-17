# 调度策略速查

本章记录 Pod 放置规则与调度排障。调度器在当前资源和约束下选择节点；亲和性、拓扑分布和优先级不能替代应用高可用、存储一致性或容量规划。

## 关键对象与边界

| 对象 | 作用 | 不负责 |
| --- | --- | --- |
| `nodeSelector` / 节点亲和性 | 筛选节点 | 驱逐不再符合标签的已运行 Pod |
| Pod 亲和性 | 让 Pod 相互靠近或分离 | 跨故障域均衡计数 |
| 拓扑分布约束 | 控制拓扑域副本差 | 自动提供节点容量 |
| PDB | 限制自愿中断 | 处理节点故障或调度放置 |

## 命令速查

### 节点与放置观察

```bash
kubectl get no --show-labels
kubectl get po -l app.kubernetes.io/name=zone-spread-api -o wide
kubectl describe no <node-name>
kubectl describe deploy zone-spread-api
```

### 创建与排障

```bash
kubectl create -f node-selector-api.yaml
kubectl create -f zone-spread-api.yaml
kubectl create -f zone-spread-api-pdb.yaml
kubectl describe po <pod-name>
kubectl get ev --field-selector involvedObject.name=<pod-name> \
  --sort-by=.metadata.creationTimestamp
```

### 优先级与 PDB

```bash
kubectl get priorityclass
kubectl get pdb
kubectl describe pdb zone-spread-api
```

## 配置速查

| 配置 | 检查重点 |
| --- | --- |
| `requiredDuringSchedulingIgnoredDuringExecution` | 仅在调度阶段强制匹配 |
| `topologyKey` | 对应节点上真实存在的稳定标签 |
| `maxSkew` | 可接受的拓扑域副本差 |
| `minAvailable` / `maxUnavailable` | 仅约束自愿中断 |

## 排查索引

| 现象 | 优先检查 | 正文 |
| --- | --- | --- |
| Pod Pending | 事件、资源、亲和性和污点 | [调度排障](./5-调度排障.md) |
| 副本未跨可用区 | topologyKey、selector、可用域容量 | [拓扑分布约束](./3-拓扑分布约束.md) |
| 节点维护被拒绝 | PDB、控制器副本与维护窗口 | [PodDisruptionBudget](./7-PodDisruptionBudget.md) |

## 关联页面

- [节点选择与约束](./1-节点选择与约束.md)
- [Pod 亲和与反亲和](./2-Pod亲和与反亲和.md)
- [高可用放置模式](./4-高可用放置模式.md)

## 参考

- [将 Pod 分配到节点](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/)
