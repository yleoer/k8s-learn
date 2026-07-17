# QoS 类别

Kubernetes 为 Pod 分配三类 QoS，顺序为 `Guaranteed`、`Burstable`、`BestEffort`。类别从实际容器资源配置推导，添加 init 容器或 sidecar 后也需要重新核对。

| 类别 | 判定 |
| --- | --- |
| `Guaranteed` | 每个容器都声明 CPU 和内存 requests、limits，且同一资源的 request 与 limit 相等 |
| `Burstable` | 不满足 Guaranteed，且至少一个容器声明 CPU 或内存 request/limit |
| `BestEffort` | 所有容器都没有 CPU 和内存 requests、limits |

QoS 不包含 ephemeral-storage、扩展资源或业务优先级的全部语义。内存超限可触发 OOM 终止，节点压力时 kubelet 的驱逐顺序也受使用量、请求和节点配置影响，不能只凭类别预测唯一结果。

## 查看类别

```bash
kubectl get po <pod-name> -o jsonpath='{.status.qosClass}{"\n"}'
kubectl describe po <pod-name>
```

## 参考

- [QoS 类别](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/#quality-of-service-classes)
