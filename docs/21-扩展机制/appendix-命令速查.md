# 扩展机制速查

本章整理 CRD、控制器与 Operator 的 API 观察和排障命令。CRD 注册自定义 API，控制器持续协调实际状态；任一对象都不能单独替代外部系统的容量、备份或恢复设计。

## 关键对象与边界

| 对象 | 作用 | 不负责 |
| --- | --- | --- |
| CRD | 注册自定义资源 API 与 schema | 自动创建受管资源 |
| Custom Resource | 表达领域期望状态 | 保证控制器正在运行 |
| Controller | 协调期望与实际状态 | 自动拥有所有集群权限 |
| Operator | 用控制器封装领域运维 | 消除数据一致性责任 |

## 命令速查

### API 注册与自定义资源

```bash
kubectl api-resources --api-group=apiextensions.k8s.io
kubectl create ns team-a
kubectl create -f crontab-crd.yaml
kubectl get crd
kubectl get ct -n team-a
```

### 版本与权限验证

```bash
kubectl get crd crontabs.stable.example.com -o yaml
kubectl get crd crontabs.stable.example.com \
  -o jsonpath='{.status.storedVersions}{"\n"}'
kubectl auth can-i update crontabs/status -n team-a \
  --as=system:serviceaccount:team-a:crontab-controller
```

### 控制器排障

```bash
kubectl get po -A
kubectl get ev -n team-a --sort-by=.metadata.creationTimestamp
kubectl describe ct sample -n team-a
kubectl get deploy -A
```

## 配置速查

| 配置 | 检查重点 |
| --- | --- |
| `served` / `storage` | 提供 API 的版本与唯一存储版本 |
| structural schema | 类型、字段裁剪、验证与 OpenAPI 发布 |
| `status` 子资源 | 分离用户更新 spec 与控制器更新 status |
| ownerReferences | 仅适用于 Kubernetes 支持的同命名空间所有权关系 |

## 排查索引

| 现象 | 优先检查 | 正文 |
| --- | --- | --- |
| API 资源不可见 | CRD 状态、API group 与 served 版本 | [CRD 与自定义资源](./2-CRD与自定义资源.md) |
| 自定义资源 status 未更新 | 控制器 Pod、日志、RBAC 与 reconcile | [控制器协调循环](./5-控制器协调循环.md) |
| 删除后遗留外部资源 | finalizer、显式清理与恢复流程 | [CRD 与控制器排障](./8-CRD与控制器排障.md) |

## 关联页面

- [扩展模型与边界](./1-扩展模型与边界.md)
- [CRD 版本演进](./4-CRD版本演进.md)
- [控制器权限与部署](./7-控制器权限与部署.md)

## 参考

- [扩展 Kubernetes API](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/)
