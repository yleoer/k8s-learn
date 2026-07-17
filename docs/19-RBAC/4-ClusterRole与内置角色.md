# ClusterRole 与内置角色

ClusterRole 用于节点、命名空间、CRD 等集群范围资源，或用于在多个命名空间复用一套规则。为某个命名空间授权时，优先用 RoleBinding 绑定 ClusterRole；这不会把权限扩展到其他命名空间。

Kubernetes 提供 `view`、`edit`、`admin` 和 `cluster-admin` 等面向用户的默认 ClusterRole。它们会在 API Server 启动时自动修复默认规则与绑定，直接修改 `system:` 前缀角色容易在升级或重启后被覆盖。

## 聚合角色

带 `rbac.authorization.k8s.io/aggregate-to-view: "true"` 等标签的 ClusterRole，可由集群控制器聚合到 `view`、`edit` 或 `admin`。这适合让新增 CRD 的权限自动并入常用角色；被聚合的权限需要像普通集群权限一样审查，因为它会影响所有引用目标角色的主体。

## 风险边界

`cluster-admin` 绕过所有 RBAC 限制，只应提供给受控的集群管理流程。`view` 不允许读取 Secret，`edit` 允许访问某些可能用于获得 ServiceAccount 身份的工作负载路径；将默认角色直接授予生产主体前，需要按当前集群已安装的聚合规则复核。

## 聚合验证

下面完整清单为 `view` 添加读取示例 CRD 的权限。它会影响所有被授予 `view` 的主体，因此只能在隔离测试集群中创建，并应在验证后删除：

```yaml [aggregate-crontab-view.yaml]
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: aggregate-crontab-view
  labels:
    rbac.authorization.k8s.io/aggregate-to-view: "true"
rules:
  - apiGroups: ["stable.example.com"]
    resources: ["crontabs"]
    verbs: ["get", "list", "watch"]
```

```bash
kubectl create -f aggregate-crontab-view.yaml
kubectl get clusterrole view -o yaml
kubectl delete clusterrole aggregate-crontab-view
```

等待聚合控制器更新后，`view` 的 `rules` 中会出现 `stable.example.com` 的 `crontabs` 读取规则。不要直接编辑 `view` 的规则；默认角色会被 API Server 自动修复，且无法表达新增 API 的独立所有权。

## 参考

- [默认角色与角色绑定](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#default-roles-and-role-bindings)
- [聚合 ClusterRole](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#aggregated-clusterroles)
