# PriorityClass 与抢占

PriorityClass 为 Pod 提供相对调度优先级。资源不足时，调度器优先尝试放置高优先级 Pod；如果没有合适节点，高优先级 Pod 可能触发抢占，删除较低优先级 Pod 以腾出空间。

优先级不保证 Pod 一定能启动，也不替代资源 requests、配额、反亲和性或容量规划。`preemptionPolicy: Never` 可让高优先级 Pod 只等待资源而不抢占其他 Pod。

## 创建非抢占优先级

```yaml [batch-low-priority.yaml]
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: batch-low
value: 100000
globalDefault: false
preemptionPolicy: Never
description: "Low-priority batch work that must not preempt other Pods."
```

```bash
kubectl create -f batch-low-priority.yaml
kubectl get priorityclass
```

工作负载可在 Pod 模板中设置 `priorityClassName: batch-low`。PriorityClass 是非命名空间资源，`value` 一旦被生产工作负载使用，就应视为长期排序契约，避免随意调整导致抢占关系改变。

## 边界

抢占只解决调度器无法放置 Pod 时的资源让位，不能解决硬节点亲和性、不可容忍污点、PDB、卷拓扑或节点实际不可用等问题。高优先级服务仍要有明确资源请求和容量冗余。

## 参考

- [Pod 优先级与抢占](https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/)
