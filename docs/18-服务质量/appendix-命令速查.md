# 服务质量速查

本章整理 Pod QoS、节点驱逐和资源压力的观察命令。QoS 从容器 CPU 与内存 requests/limits 推导，是驱逐决策因素之一，不是可用性、优先级或容量规划的替代品。

## 关键对象与边界

| 对象 | 作用 | 不负责 |
| --- | --- | --- |
| QoS | 分类 Pod 的资源配置模式 | 指定业务优先级 |
| OOMKilled | 标识容器内存超限后的终止 | 说明节点已发生驱逐 |
| Evicted | 标识节点压力驱逐 | 说明容器 limit 一定不足 |
| PriorityClass | 排序调度与抢占优先级 | 定义 QoS |

## 命令速查

### Pod QoS 与终止原因

```bash
kubectl get po <pod-name> -o jsonpath='{.status.qosClass}{"\n"}'
kubectl describe po <pod-name>
kubectl get po <pod-name> -o jsonpath='{.status.containerStatuses[*].state.terminated.reason}{"\n"}'
```

### 节点压力观察

```bash
kubectl top no
kubectl top po -A --containers
kubectl describe no <node-name>
kubectl get ev -A --sort-by=.metadata.creationTimestamp
kubectl get po -A --field-selector=status.phase=Failed
```

## 配置速查

| 配置 | 检查重点 |
| --- | --- |
| `Guaranteed` | 每个容器 CPU、内存的 request 与 limit 均存在且相等 |
| `Burstable` | 至少一个容器声明 CPU 或内存资源，但不满足 Guaranteed |
| `BestEffort` | 所有容器都没有 CPU 和内存 requests/limits |
| requests | 调度与资源预留依据，不等于实时使用量 |

## 排查索引

| 现象 | 优先检查 | 正文 |
| --- | --- | --- |
| `OOMKilled` | 容器内存需求、limit 与应用行为 | [驱逐与 OOM 边界](./3-驱逐与OOM边界.md) |
| `Evicted` | 节点条件、驱逐阈值和压力来源 | [资源压力排障](./4-资源压力排障.md) |
| QoS 与预期不同 | 最终 Pod 规范中的每个容器资源 | [QoS 类别](./1-QoS类别.md) |

## 关联页面

- [资源配置模式](./2-资源配置模式.md)
- [资源配额](../16-资源配额/index.md)
- [限制范围](../17-限制范围/index.md)

## 参考

- [Pod 服务质量类别](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/)
