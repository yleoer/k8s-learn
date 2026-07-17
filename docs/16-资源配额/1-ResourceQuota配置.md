# ResourceQuota 配置

ResourceQuota 的 `spec.hard` 定义命名空间上限，控制平面在创建或更新资源时拒绝会超过上限的请求。`status.used` 由控制器计算，不能作为手工维护的配置来源。

## 计算和对象配额

```yaml [team-a-quota.yaml]
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-a-quota
  namespace: team-a
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    pods: "20"
    services: "10"
    persistentvolumeclaims: "5"
    requests.storage: 100Gi
```

```bash
kubectl create ns team-a
kubectl create -f team-a-quota.yaml
kubectl get quota -n team-a
kubectl describe quota team-a-quota -n team-a
```

`requests.cpu` 与 `limits.cpu` 分别累加非终止 Pod 的 CPU 请求和限制；内存字段同理。对象计数资源使用复数资源名，例如 `pods`、`services` 与 `persistentvolumeclaims`。

> [!IMPORTANT]
> 命名空间存在计算资源配额时，创建的 Pod 必须能满足所要求的 requests 或 limits。通常应同时配置 LimitRange 以提供默认值，否则未声明资源的工作负载会被拒绝。

## 参考

- [计算资源配额](https://kubernetes.io/docs/concepts/policy/resource-quotas/#compute-resource-quota)
- [对象数量配额](https://kubernetes.io/docs/concepts/policy/resource-quotas/#quota-on-object-count)
