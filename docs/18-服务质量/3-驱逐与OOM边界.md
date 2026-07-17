# 驱逐与 OOM 边界

内存不足和节点压力是不同层次的事件。容器超过内存 limit 时，Linux 内核可能 OOM 终止进程；节点触发内存、磁盘或 PID 压力时，kubelet 会根据驱逐阈值和候选 Pod 情况回收节点资源。

QoS 是驱逐考虑因素之一，但不是“Guaranteed 永不驱逐”的承诺。系统守护进程、可分配资源、临界阈值、Pod 使用量、requests、优先级和节点条件共同影响结果。

## 观察路径

```bash
kubectl describe po <pod-name>
kubectl get po <pod-name> -o jsonpath='{.status.containerStatuses[*].state.terminated.reason}{"\n"}'
kubectl describe no <node-name>
kubectl get ev --sort-by=.metadata.creationTimestamp
```

`OOMKilled` 说明容器曾被内核终止；`Evicted` 表示 Pod 因节点压力被驱逐。两者对应的修复方向不同：前者审查容器内存需求与 limit，后者还要审查节点容量、系统保留和压力来源。

> [!WARNING]
> 把所有服务改为 Guaranteed 会把更多容量变成刚性请求，可能降低集群弹性并增加调度失败。应为每类服务建立经测量的 requests/limits 基线。

## 参考

- [节点压力驱逐](https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/)
