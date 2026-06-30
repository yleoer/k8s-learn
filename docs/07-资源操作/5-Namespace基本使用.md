# Namespace 基本使用

Namespace 是 Kubernetes 中最常用的逻辑隔离方式。它可以把同一个集群划分为多个相对独立的资源空间，让不同团队、项目或环境在同一套集群中管理自己的资源。

## 为什么需要 Namespace

生产集群通常会承载多个应用、多个环境或多个团队。如果所有资源都堆在同一个空间里，资源命名、权限控制、配额管理和日常排障都会变得混乱。

Namespace 可以解决以下问题：

| 场景 | Namespace 的作用 |
| --- | --- |
| 多环境 | 按 `dev`、`test`、`prod` 划分资源 |
| 多团队 | 按团队或业务线划分资源边界 |
| 权限控制 | 配合 RBAC 控制用户能访问哪些资源 |
| 资源配额 | 配合 ResourceQuota 限制资源总量 |
| 默认配置 | 配合 LimitRange 设置容器资源默认值 |
| 运维管理 | 按 Namespace 查看、备份、迁移或清理资源 |

Namespace 可以理解为集群中的“逻辑工作区”，但它不是强隔离的虚拟集群。

## Namespace 的边界

Namespace 只隔离命名空间级资源，例如 Pod、Deployment、Service、ConfigMap、Secret 等。

```bash
kubectl api-resources --namespaced=true
```

也有一些资源不属于任何 Namespace，例如 Node、Namespace、PersistentVolume、StorageClass、ClusterRole 等。

```bash
kubectl api-resources --namespaced=false
```

这类资源属于整个集群，不能通过 `-n` 指定 Namespace。

## 常见划分方式

按环境划分：

```text
dev
test
staging
prod
```

按团队划分：

```text
team-a
team-b
platform
middleware
```

按业务划分：

```text
order
payment
member
search
```

实际生产环境常把团队、业务和环境结合起来，例如 `order-dev`、`order-prod`。命名应尽量简单、一致、可读。

## Namespace 与访问控制

Namespace 自身不提供权限控制。要限制用户只能操作某个 Namespace，需要配合 RBAC：

- `Role` 定义某个 Namespace 内的权限
- `RoleBinding` 把权限绑定给用户、用户组或 ServiceAccount
- `ClusterRole` 定义集群级权限或可复用权限模板
- `ClusterRoleBinding` 绑定集群级权限

因此，Namespace 负责资源分组，RBAC 负责访问授权，两者经常配合使用。

## Namespace 与资源限制

Namespace 也经常配合资源治理对象使用：

| 资源 | 作用 |
| --- | --- |
| `ResourceQuota` | 限制某个 Namespace 可使用的总资源 |
| `LimitRange` | 限制或默认化单个 Pod、容器的资源请求与上限 |
| `NetworkPolicy` | 限制 Pod 之间的网络访问 |

如果只创建 Namespace，而不配置配额、权限和网络策略，它更多只是一个逻辑分组。

## 使用建议

Namespace 适合用于：

- 环境隔离
- 团队资源边界
- 权限与配额落点
- 按范围查看和管理资源

Namespace 不适合用于：

- 替代集群级安全隔离
- 隔离 Node、PV 等集群级资源
- 作为强多租户的唯一手段

本文先记录 Namespace 的创建、查看、切换和删除。后续 RBAC、ResourceQuota、LimitRange 和 NetworkPolicy 章节会继续扩展它的治理能力。

## 默认 Namespace

新建 Kubernetes 集群后，通常会自带几个默认 Namespace：

| Namespace | 用途 |
| --- | --- |
| `default` | 未指定 Namespace 时使用的默认空间 |
| `kube-system` | Kubernetes 系统组件所在空间 |
| `kube-public` | 所有用户通常都可读取的公共空间 |
| `kube-node-lease` | 保存节点 Lease 对象，用于节点心跳机制 |

查看默认 Namespace：

```bash
kubectl get namespace
kubectl get ns
```

实验环境可以把临时资源放在 `default` 中。生产环境不建议把所有业务资源都放在 `default`，否则权限、配额、监控和清理都会变得不清晰。

`kube-system` 中通常运行 CoreDNS、kube-proxy、CNI 插件、metrics-server 等系统组件，不要随意删除或修改其中资源。`kube-public` 不应放置敏感配置。`kube-node-lease` 通常不需要手工维护。

## 创建 Namespace

使用命令创建：

```bash
kubectl create namespace dev
kubectl create ns test
```

使用 YAML 创建：

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: dev
```

应用 YAML：

```bash
kubectl apply -f namespace-dev.yaml
```

生产环境更推荐使用 YAML 管理 Namespace，方便纳入版本控制。

## 查看 Namespace

查看所有 Namespace：

```bash
kubectl get namespace
kubectl get ns
```

查看指定 Namespace：

```bash
kubectl get namespace dev
kubectl get namespace dev --show-labels
kubectl describe namespace dev
```

`describe` 可以看到 Namespace 状态、标签、注解和资源配额等信息。

## 在指定 Namespace 中创建资源

命令方式：

```bash
kubectl create deployment nginx --image=nginx:1.25 -n dev
kubectl get deployment -n dev
kubectl get pod -n dev
```

YAML 方式：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
```

资源 YAML 中的 `metadata.namespace` 表示该资源所属的 Namespace。如果 YAML 中没有指定，则会使用 kubectl 当前上下文的默认 Namespace。

## 切换默认 Namespace

可以为当前上下文设置默认 Namespace：

```bash
kubectl config set-context --current --namespace=dev
kubectl config view --minify
```

恢复为 `default`：

```bash
kubectl config set-context --current --namespace=default
```

为了避免误操作，执行变更前建议确认当前上下文：

```bash
kubectl config current-context
kubectl config view --minify
```

## 查询所有 Namespace 的资源

使用 `-A` 或 `--all-namespaces`：

```bash
kubectl get pod -A
kubectl get service --all-namespaces
kubectl get deployment -A
```

排查集群级问题时，`-A` 很常用；处理具体业务问题时，则优先指定明确的 Namespace。

## 删除 Namespace

删除 Namespace：

```bash
kubectl delete namespace dev
```

删除 Namespace 会连带删除其下的大多数资源，包括 Pod、Deployment、Service、ConfigMap、Secret 等。这个操作影响较大，生产环境必须谨慎。

有时删除 Namespace 会停留在 `Terminating` 状态，常见原因包括带 finalizer 的资源未完成清理、某些 APIService 不可用、控制器无法完成资源清理等。遇到该问题时，先用 `kubectl describe namespace <namespace>` 查看原因。

## 命名规则

Namespace 名称需要符合 DNS 标签格式。常见要求包括：

- 只能包含小写字母、数字和中横线
- 以字母或数字开头和结尾
- 通常不超过 63 个字符

推荐命名：

```text
dev
test
prod
team-a
order-prod
```
