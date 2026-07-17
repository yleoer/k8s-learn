# Operator 模式与 Helm

Helm 与 Operator 可以协作，但解决的问题不同。Helm 负责把 Chart 渲染并提交给 API Server；Operator 持续观察资源和外部状态，并在运行期间协调。用 Helm 安装 Operator 本身是常见做法，安装完成不等于由 Helm 持续运维被管理对象。

| 维度 | Helm | Operator |
| --- | --- | --- |
| 主职责 | 模板化发布 | 持续控制循环 |
| 集群内常驻组件 | 无 | 通常有 controller Deployment |
| 状态来源 | Release 历史与 Kubernetes 对象 | 自定义资源 spec/status 与实际状态 |
| 适合场景 | 应用清单、固定发布流程 | 有状态系统、外部系统或复杂生命周期 |
| 主要风险 | 模板、值和升级差异 | 控制器权限、协调错误、版本兼容和运维负担 |

Operator 不应自动拥有 `cluster-admin`。其 RBAC 应限制到自定义 API 及实际受管的资源，凭据、外部系统权限、备份和恢复路径必须独立审查。

## 分离验证

Helm 的验证重点是渲染与 Release，Operator 的验证重点是控制器是否持续协调。使用已安装的 Operator 时，可先观察这两层对象，而不把 Helm Release 成功误判为受管资源已就绪：

```bash
helm list -A
kubectl get crd
kubectl get deploy -A
kubectl get ev -A --sort-by=.metadata.creationTimestamp
```

具体 Operator 的 Deployment 名称、标签和自定义资源类型由实现决定。安装前先用 `helm template` 审查对应 Chart；安装后按[CRD 与控制器排障](./8-CRD与控制器排障.md#检查顺序)检查 API 注册、控制器日志和资源状态。

## 参考

- [Operator 模式](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)
- [Helm 安全模型](https://helm.sh/docs/topics/security/)
