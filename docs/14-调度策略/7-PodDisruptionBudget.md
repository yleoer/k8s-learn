# PodDisruptionBudget

PodDisruptionBudget（PDB）限制自愿中断期间可同时不可用的 Pod 数量，例如节点 drain、集群升级或自愿 Pod 删除。PDB 不阻止应用崩溃、节点故障、OOM 或调度器抢占等非自愿中断。

PDB 的 selector 必须匹配一个或多个控制器管理的 Pod。`minAvailable` 与 `maxUnavailable` 只能二选一；单副本服务设置 PDB 并不能创造冗余，反而可能阻塞必要的节点维护。

## 保护多副本 API

下面清单复用 [拓扑分布约束](/14-调度策略/3-拓扑分布约束) 中 `zone-spread-api.yaml` 创建的 Deployment 及其 `app.kubernetes.io/name=zone-spread-api` 标签：

```yaml [zone-spread-api-pdb.yaml]
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: zone-spread-api
spec:
  minAvailable: 4
  selector:
    matchLabels:
      app.kubernetes.io/name: zone-spread-api
```

```bash
kubectl create -f zone-spread-api-pdb.yaml
kubectl get pdb zone-spread-api
kubectl describe pdb zone-spread-api
```

`minAvailable: 4` 对六副本服务允许最多两个自愿中断。滚动更新的可用性还受 Deployment 策略、readiness 和终止排空影响，不能只依赖 PDB。

## 参考

- [指定中断预算](https://kubernetes.io/docs/tasks/run-application/configure-pdb/)
