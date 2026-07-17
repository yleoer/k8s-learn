# 工作负载访问 API

工作负载访问 Kubernetes API 时，应为每个用途创建独立 ServiceAccount，并通过最小 RoleBinding 授权。不要复用 `default` ServiceAccount，也不要把开发人员的交互式身份绑定到自动化工作负载。

## 只读 ConfigMap 示例

```yaml [config-reader-rbac.yaml]
apiVersion: v1
kind: ServiceAccount
metadata:
  name: config-reader
  namespace: team-a
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: read-app-config
  namespace: team-a
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    resourceNames: ["app-config"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: config-reader
  namespace: team-a
subjects:
  - kind: ServiceAccount
    name: config-reader
    namespace: team-a
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: read-app-config
```

规则中的 `resourceNames` 仅适用于命名对象的请求，不能替代列表过滤。若应用需要 watch 或 list，它将无法依靠 `resourceNames` 获得只看单个对象的语义，应重新设计配置分发方式。

## 参考

- [引用资源](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#referring-to-resources)
