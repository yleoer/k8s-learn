# LimitRange 排障

LimitRange 失败通常在创建或更新请求时返回，错误会说明哪个最小值、最大值或比例约束不满足。容器资源设置还会影响 QoS 和 ResourceQuota，因此排障应查看最终 Pod 规范。

## 检查顺序

```bash
kubectl get limitrange -n team-a
kubectl describe limitrange team-a-limits -n team-a
kubectl get po <pod-name> -n team-a -o yaml
kubectl get quota -n team-a
kubectl get ev -n team-a --sort-by=.metadata.creationTimestamp
```

重点比较每个容器的 `requests`、`limits` 与 LimitRange。Pod 级别资源和容器级资源并存时，应基于集群版本与 API 文档判断具体准入和 QoS 语义，不把容器默认值简单套用到 Pod 级字段。

> [!CAUTION]
> 不要通过删除 LimitRange 让一次部署通过。这会让同命名空间后续对象失去单对象约束，并可能导致配额和 QoS 行为整体变化。

## 参考

- [LimitRange 准入](https://kubernetes.io/docs/concepts/policy/limit-range/#limitrange)
