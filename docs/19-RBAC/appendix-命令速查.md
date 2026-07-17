# RBAC 命令速查

本章整理 ServiceAccount、Role、ClusterRole、Binding 与 kubeconfig 的观察和验证命令。RBAC 只回答某个身份是否被授权访问 Kubernetes API，不替代准入、网络策略或应用自身认证。

## 关键对象与边界

| 对象 | 作用 | 不负责 |
| --- | --- | --- |
| ServiceAccount | 工作负载 API 身份 | 人类用户身份管理 |
| Role / RoleBinding | 命名空间范围授权 | 集群范围授权 |
| ClusterRole / ClusterRoleBinding | 集群范围或可复用规则 | 自动限定命名空间 |
| kubeconfig context | 选择集群、用户和命名空间 | 授予额外权限 |

## 命令速查

### 创建与查看

```bash
kubectl create -f team-a-developer-rbac.yaml
kubectl get sa -n team-a
kubectl get role,rolebinding -n team-a
kubectl get clusterrole,clusterrolebinding
kubectl describe role workload-viewer -n team-a
```

### 权限验证

```bash
kubectl auth can-i get po -n team-a \
  --as=system:serviceaccount:team-a:developer
kubectl auth can-i get po/log -n team-a \
  --as=system:serviceaccount:team-a:developer
kubectl auth can-i create po/exec -n team-a \
  --as=system:serviceaccount:team-a:developer
kubectl auth can-i --list -n team-a \
  --as=system:serviceaccount:team-a:developer
```

### 用户与凭据

```bash
kubectl get csr
kubectl describe csr <csr-name>
kubectl certificate approve <csr-name>
kubectl config get-contexts
kubectl config current-context
```

## 配置速查

| 配置 | 检查重点 |
| --- | --- |
| `apiGroups` / `resources` / `verbs` | 精确匹配请求的 API 与动作 |
| 子资源 | `pods/log`、`pods/exec` 必须单独授权 |
| `roleRef` | 不可变，更换角色需重建 Binding |
| `aggregate-to-view` | 会影响所有引用默认 `view` 角色的主体 |

## 排查索引

| 现象 | 优先检查 | 正文 |
| --- | --- | --- |
| `Forbidden` | 身份、API group、资源、子资源、verb 和 Binding | [授权验证与排障](./5-授权验证与排障.md) |
| 工作负载无法访问 API | ServiceAccount、投射令牌和 RoleBinding | [工作负载访问 API](./6-工作负载访问API.md) |
| 默认角色权限意外扩大 | 聚合 ClusterRole 与已安装 CRD | [ClusterRole 与内置角色](./4-ClusterRole与内置角色.md) |

## 关联页面

- [认证主体与授权边界](./1-认证主体与授权边界.md)
- [用户凭据与 kubeconfig](./7-用户凭据与Kubeconfig.md)

## 参考

- [使用 RBAC 授权](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
