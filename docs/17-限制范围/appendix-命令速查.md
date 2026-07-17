# 限制范围速查

本章整理 LimitRange 的默认值、最小值、最大值和比例约束。LimitRange 限制单个对象，ResourceQuota 限制命名空间总量；两者需要配合，不能互相替代。

## 关键对象与边界

| 对象 | 作用 | 不负责 |
| --- | --- | --- |
| LimitRange | 校验并默认化单对象资源 | 限制命名空间总量 |
| Container limit | 约束单容器资源配置 | 表示实际瞬时用量 |
| PVC limit | 约束单个 PVC 请求范围 | 保证存储供给成功 |

## 命令速查

### 创建与验证

```bash
kubectl create -f team-a-limits.yaml
kubectl get limitrange -n team-a
kubectl describe limitrange team-a-limits -n team-a
kubectl get po <pod-name> -n team-a -o yaml
```

### 联合观察

```bash
kubectl get quota -n team-a
kubectl get pvc -n team-a
kubectl get ev -n team-a --sort-by=.metadata.creationTimestamp
```

## 配置速查

| 配置 | 检查重点 |
| --- | --- |
| `default` | 未填写 limit 时注入的默认值 |
| `defaultRequest` | 未填写 request 时注入的默认请求 |
| `min` / `max` | 单对象资源边界 |
| `maxLimitRequestRatio` | limit 与 request 的最大比例 |

## 排查索引

| 现象 | 优先检查 | 正文 |
| --- | --- | --- |
| 创建被拒绝 | min、max、比例与容器资源 | [LimitRange 排障](./4-LimitRange排障.md) |
| QoS 与预期不符 | 最终 Pod 的 requests/limits | [资源默认值验证](./3-资源默认值验证.md) |
| PVC 超出范围 | PVC 请求与存储 LimitRange | [PVC 范围与配额配合](./2-PVC范围与配额配合.md) |

## 关联页面

- [LimitRange 资源](./1-LimitRange资源.md)
- [资源配额](../16-资源配额/index.md)

## 参考

- [LimitRange](https://kubernetes.io/docs/concepts/policy/limit-range/)
