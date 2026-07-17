# Namespace 基本使用

Namespace 是 Kubernetes 中的集群级对象，用来为命名空间级资源提供名称作用域和治理范围。它不是虚拟集群、Node 隔离或网络隔离机制；同一个集群中的不同 Namespace 仍共享控制面、节点、网络插件和集群级资源。

## 名称作用域与资源范围

Namespace 的首要作用是让资源名称在不同逻辑空间内复用。例如，`dev` 和 `prod` 都可以创建名为 `api` 的 Deployment；但同一 Namespace 中不能存在两个同类型、同名称的 `api` 对象。Namespace 不能嵌套，且 Namespace 对象本身不属于任何 Namespace。

| 作用域 | 典型对象 | 名称唯一性 |
| --- | --- | --- |
| 命名空间级 | Pod、Deployment、Service、ConfigMap、Secret、PVC、Role | 只需在所属 Namespace 内唯一 |
| 集群级 | Node、Namespace、PV、StorageClass、ClusterRole | 在整个集群范围内唯一 |

```bash
kubectl api-resources --namespaced=true
kubectl api-resources --namespaced=false
```

资源是否属于 Namespace 由 API 定义决定。给 `kubectl get no` 传入 `-n dev` 不会把 Node 变成命名空间级资源，也不会限制 Node 查询范围。

## 对象归属与 kubectl 默认值

命名空间级对象的实际归属记录在 `metadata.namespace` 中：

```yaml{5} [nginx-dev-deploy.yaml]
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
          image: nginx:1.31-alpine
```

`metadata.namespace` 是对象字段；kubeconfig context 中的 Namespace 和命令行 `-n` 则是 kubectl 选择请求范围的方式。清单未写 `metadata.namespace` 时，kubectl 使用 `-n` 或当前 context 的默认 Namespace。长期维护的清单应明确写出对象归属，临时查询则优先显式传入 `-n`。

```bash
kubectl create deploy nginx --image=nginx:1.31-alpine -n dev
kubectl get deploy -n dev
kubectl get po -n dev
```

首次创建上面的清单：

```bash
kubectl create -f nginx-dev-deploy.yaml
```

context 的 cluster、user 和默认 Namespace 如何影响 kubectl 请求，见[kubeconfig 与上下文](./1-kubectl命令基础.md#kubeconfig-与上下文)。

## 默认系统 Namespace

新建 Kubernetes 集群通常包含以下 Namespace：

| Namespace | 用途与边界 |
| --- | --- |
| `default` | 未指定 Namespace 时的默认空间，适合临时验证，不宜作为所有业务资源的统一落点 |
| `kube-system` | Kubernetes 系统组件和集群插件所在空间，不应随意删除或修改其中对象 |
| `kube-public` | 默认可被所有客户端读取的公共空间，不应保存敏感信息；其“公开”属性是使用约定而非安全边界 |
| `kube-node-lease` | 保存与 Node 同名的 Lease，供 kubelet 心跳和节点健康判断使用 |

```bash
kubectl get ns
kubectl get ns --show-labels
kubectl describe ns dev
```

## 服务名称与 Namespace

Service 名称同样受 Namespace 作用域影响。Pod 在同一 Namespace 内访问 `redis` 时，DNS 可以解析本空间的同名 Service；跨 Namespace 时应包含目标 Namespace：

```text
redis
redis.dev
redis.dev.svc.cluster.local
```

其中 `redis` 是 Service 名称，`dev` 是 Namespace，`svc` 表示 Service DNS 子域，`cluster.local` 是常见默认集群域名。Namespace 解决的是名称作用域，Service 如何选择后端 Pod、EndpointSlice 如何维护端点以及 DNS 如何解析，在第 10 章展开。

## 治理边界

Namespace 只提供分组和作用域。多团队或多环境共用集群时，还要在 Namespace 上叠加不同治理对象：

| 对象或机制 | 解决的问题 | Namespace 本身不负责的部分 |
| --- | --- | --- |
| RBAC | 限制某个身份可对哪些资源执行哪些动作 | Namespace 不会自动授予或拒绝权限 |
| ResourceQuota | 限制 Namespace 的 Pod 数、CPU、内存、存储等总量 | 不为单个容器设置默认值或上下限 |
| LimitRange | 约束或默认化单个 Pod、容器和 PVC 的资源范围 | 不限制 Namespace 的资源总量 |
| NetworkPolicy | 声明哪些 Pod 流量被允许 | 需要支持该能力的 [CNI 网络插件](../06-集群架构/5-工作节点组件.md#cni-网络插件) 实际执行 |

RBAC 中的 Role 与 RoleBinding 通常作用于一个 Namespace；ClusterRole 与 ClusterRoleBinding 可授予集群级或可复用权限。NetworkPolicy 是 Kubernetes API 对象，不是网络转发程序；是否真正阻断流量取决于所选 CNI 是否支持并启用策略执行。第 16～19 章分别记录资源治理和 RBAC，网络策略的实现边界随网络插件而变化。

## 创建、查询与删除

可以直接创建 Namespace：

```bash
kubectl create ns dev
```

需要长期维护时，使用完整清单：

```yaml [namespace-team-a.yaml]
apiVersion: v1
kind: Namespace
metadata:
  name: team-a
```

首次提交：

```bash
kubectl create -f namespace-team-a.yaml
```

跨 Namespace 查询命名空间级资源：

```bash
kubectl get po -A
kubectl get svc -A
kubectl get deploy -A
```

删除 Namespace：

```bash
kubectl delete ns dev
```

删除 Namespace 会启动异步清理：Namespace Controller 会删除其中的命名空间级对象，并等待这些对象的 finalizer 完成清理。finalizer 是对象上的保护标记，用来确保外部资源、卷或控制器清理完成后再移除对象；因此 Namespace 会先进入 `Terminating`，而不是立即消失。

> [!CAUTION]
> Namespace 长时间处于 `Terminating` 时，应使用 `kubectl describe ns <namespace>` 查找未完成清理的对象、finalizer 或不可用的扩展 API。直接移除 finalizer 可能遗留云资源、存储或其他外部依赖，只能在已确认清理后作为恢复手段。

## 命名建议

Namespace 名称符合 RFC 1123 DNS 标签规则：只能包含小写字母、数字和中横线，以字母或数字开头和结尾，长度不超过 63 个字符。避免使用 `kube-` 前缀，该前缀保留给 Kubernetes 系统 Namespace。

```text
dev
team-a
order-prod
```
