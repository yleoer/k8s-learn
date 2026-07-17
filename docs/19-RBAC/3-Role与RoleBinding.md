# Role 与 RoleBinding

Role 保存命名空间内的一组 API 访问规则，RoleBinding 将它授予主体。下面的完整清单允许 `team-a` 中的 `developer` ServiceAccount 读取 Pod、日志和 Service，并查看 Deployment；它不授予创建、删除、执行命令或读取 Secret 的权限。

```yaml [team-a-developer-rbac.yaml]
apiVersion: v1
kind: ServiceAccount
metadata:
  name: developer
  namespace: team-a
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: workload-viewer
  namespace: team-a
rules:
  - apiGroups: [""]
    resources: ["pods", "services"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: developer-workload-viewer
  namespace: team-a
subjects:
  - kind: ServiceAccount
    name: developer
    namespace: team-a
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: workload-viewer
```

```bash
kubectl create -f team-a-developer-rbac.yaml
kubectl auth can-i get po/log -n team-a \
  --as=system:serviceaccount:team-a:developer
```

`roleRef` 是不可变字段。需要更换绑定角色时，应删除并重新创建 Binding；不要试图通过 patch 改写其引用。

## 参考

- [Role 与 ClusterRole](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#role-and-clusterrole)
- [RoleBinding 与 ClusterRoleBinding](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#rolebinding-and-clusterrolebinding)
