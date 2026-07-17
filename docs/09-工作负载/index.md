# 工作负载

第 08 章已经记录 Pod 资源定义、生命周期和健康检查等基础内容。本章在 Pod 基础之上引入工作负载控制器，从单实例运行进入多副本、有序身份和节点级守护进程管理阶段。

本章围绕 Deployment、StatefulSet 和 DaemonSet 展开，覆盖无状态服务、有状态应用和节点级组件的典型调度方式。这些内容将为后续 Service、Ingress、配置管理、存储和集群运维组件部署提供基础支撑。

## 工作负载控制器

直接创建 Pod 有助于明确 Kubernetes 最小可部署单元的边界，但生产环境通常不会长期使用裸 Pod 承载业务。Pod 退出后不会自动维持副本数，也缺少滚动更新、版本回滚和统一扩缩容能力。

Kubernetes 提供了一组工作负载控制器，用于持续维护业务期望状态。无状态服务通常使用 Deployment，有状态服务通常使用 StatefulSet，节点级守护进程通常使用 DaemonSet。

常见调度资源可以按业务形态划分：

| 资源 | 典型场景 | 核心能力 |
| --- | --- | --- |
| `Deployment` | Web 服务、API 服务、微服务 | 多副本、滚动更新、回滚、扩缩容 |
| `ReplicaSet` | Deployment 底层副本控制 | 维持 Pod 副本数量 |
| `ReplicationController` | 早期副本控制器 | 维持 Pod 副本数量 |
| `StatefulSet` | 数据库、注册中心、有序集群 | 稳定网络标识、稳定存储、有序发布 |
| `DaemonSet` | 日志采集、监控 Agent、节点插件 | 稳定状态下按匹配节点各运行一份 Pod |

## 副本控制器

ReplicationController 简称 RC，是 Kubernetes 早期提供的副本控制器。它通过 `selector` 匹配一组 Pod，并维持匹配到的 Pod 数量等于 `spec.replicas`。

ReplicaSet 简称 RS，是 RC 的下一代实现。它同样用于维持 Pod 副本数，但支持更丰富的标签选择器。

| 对比项 | ReplicationController | ReplicaSet |
| --- | --- | --- |
| API 版本 | `v1` | `apps/v1` |
| 主要职责 | 维持 Pod 副本数量 | 维持 Pod 副本数量 |
| 标签选择器 | 等值匹配 | 等值匹配与集合表达式 |
| 当前定位 | 早期资源，作为背景保留 | Deployment 底层资源 |
| 生产建议 | 不建议新建使用 | 由 Deployment 自动管理 |

ReplicaSet 支持 `matchLabels` 和 `matchExpressions`：

```yaml{7-19} [nginx-rs-selector.yaml]
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: nginx-rs-selector
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
    matchExpressions:
      - key: tier
        operator: In
        values:
          - frontend
  template:
    metadata:
      labels:
        app: nginx
        tier: frontend
    spec:
      containers:
        - name: nginx
          image: nginx:1.31-alpine
```

现代 Kubernetes 中更常见的是 Deployment。Deployment 会自动创建和管理 ReplicaSet，再由 ReplicaSet 管理 Pod，因此实际使用中通常不直接操作 ReplicaSet 或 ReplicationController。

### RS 与 Pod 的关系

ReplicaSet 通过标签选择器关联 Pod，并不直接记录某几个 Pod 的名称。控制器持续观察匹配标签的 Pod 数量：实际数量少于期望值时创建新 Pod，多于期望值时删除多余 Pod。

下面示例使用 ReplicaSet 创建 3 个 Pod：

```yaml [nginx-rs.yaml]
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: nginx-rs
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx-rs
  template:
    metadata:
      labels:
        app: nginx-rs
    spec:
      containers:
        - name: nginx
          image: nginx:1.31-alpine
          ports:
            - containerPort: 80
```

创建并查看：

```bash
kubectl create -f nginx-rs.yaml
kubectl get rs
kubectl get po -l app=nginx-rs -o wide
```

删除一个被 RS 管理的 Pod：

```bash
kubectl delete po -l app=nginx-rs
kubectl get po -l app=nginx-rs -w
```

ReplicaSet 会重新创建新的 Pod，使副本数量回到 3。如果要真正删除这组 Pod，应删除控制器：

```bash
kubectl delete rs nginx-rs
```

## 参考

本章背景内容参考以下 Kubernetes 英文文档：

- [工作负载](https://kubernetes.io/docs/concepts/workloads/)
- [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [ReplicaSet](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/)
- [ReplicationController](https://kubernetes.io/docs/concepts/workloads/controllers/replicationcontroller/)
