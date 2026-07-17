# 资源配额速查

本章整理命名空间总量约束与治理命令。ResourceQuota 限制对象数量和资源总量，不负责为 Pod 提供默认资源，也不保证节点或后端存储有足够容量。

## 关键对象与边界

| 对象 | 作用 | 不负责 |
| --- | --- | --- |
| ResourceQuota | 限制命名空间资源总量 | 设置单个容器默认值 |
| scope / scopeSelector | 将统计限定到匹配对象 | 改变 Pod 调度优先级 |
| StorageClass 配额 | 限制指定类的 PVC 请求 | 供给后端卷 |

## 命令速查

### 创建治理边界

```bash
kubectl create ns team-a
kubectl create -f team-a-quota.yaml
kubectl create -f team-a-limits.yaml
kubectl create -f team-a-developer-rbac.yaml
```

完整清单分别见[ResourceQuota 配置](./1-ResourceQuota配置.md#计算和对象配额)、[LimitRange 资源](../17-限制范围/1-LimitRange资源.md#容器默认值与范围)和[Role 与 RoleBinding](../19-RBAC/3-Role与RoleBinding.md)。

### 配额观察

```bash
kubectl get quota -n team-a
kubectl describe quota team-a-quota -n team-a
kubectl get po -n team-a
kubectl get pvc -n team-a
kubectl get ev -n team-a --sort-by=.metadata.creationTimestamp
```

## 配置速查

| 配置 | 检查重点 |
| --- | --- |
| `hard` | 资源键与最大可用总量 |
| `used` | 控制器维护的当前统计，不手动编辑 |
| `scopeSelector` | scopeName 与 values 必须符合 API 支持范围 |
| `requests.storage` | PVC 请求容量总和，不等于已实际供给容量 |

## 排查索引

| 现象 | 优先检查 | 正文 |
| --- | --- | --- |
| API 拒绝创建 | `hard`、`used` 与待创建对象资源 | [配额观察与排障](./4-配额观察与排障.md) |
| PVC 被拒绝 | StorageClass 配额与 PVC 请求 | [配额范围与存储](./2-配额范围与存储.md) |
| 首个 Pod 未受约束 | 创建顺序与 LimitRange | [命名空间治理](./3-命名空间治理.md) |

## 关联页面

- [限制范围](../17-限制范围/index.md)
- [服务质量](../18-服务质量/index.md)

## 参考

- [资源配额](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
