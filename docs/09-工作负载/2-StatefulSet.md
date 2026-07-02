# StatefulSet

StatefulSet 用于管理需要稳定身份、稳定存储和有序变更的有状态应用。它同样使用声明式方式描述期望状态，但每个副本都拥有固定序号、可预测网络标识和跨重调度保持的粘性身份。

本文将 StatefulSet 相关内容合并为一个文档，内容包括基础与创建、Headless Service 与内部通信、更新扩缩容和版本管理。

## StatefulSet 基础与创建

Deployment 适合管理无状态副本，任意 Pod 被替换后都可以继续承接请求。有些应用则依赖稳定身份、固定存储或有序启动，例如数据库、注册中心和分布式协调组件，这类应用通常更适合使用 StatefulSet。

StatefulSet 是 Kubernetes 中用于管理有状态应用的工作负载控制器。它同样使用声明式配置描述期望状态，但会为每个 Pod 分配稳定的序号、稳定的网络标识，并可以结合存储卷声明为每个副本维护独立数据。这些 Pod 来自同一模板，但彼此不可互换。

### 适用场景

StatefulSet 常用于以下场景：

- 需要稳定且唯一的网络标识
- 需要稳定的持久化数据
- 需要按固定顺序启动、扩容或缩容
- 需要按固定顺序滚动更新
- 集群成员之间需要通过固定名称相互发现

典型应用包括 MySQL 主从集群、ZooKeeper、etcd、Kafka、Redis Cluster、Eureka 集群等。它们通常不只关心“有几个副本”，还关心“每个副本是谁”。其中 Eureka 属于特定 Spring Cloud / Netflix 技术栈语境；在 Kubernetes 内部服务发现中，应优先评估 Service 和 DNS 是否已经满足需求。

StatefulSet 管理的 Pod 名称具有固定序号：

```text
web-0
web-1
web-2
```

这些名称不会像 Deployment 管理的 Pod 那样带随机后缀。即使 Pod 被删除重建，新 Pod 仍会使用原来的名称和序号。

### 与 Deployment 对比

| 对比项 | Deployment | StatefulSet |
| --- | --- | --- |
| 主要场景 | 无状态服务 | 有状态服务 |
| Pod 名称 | 随机后缀 | 固定序号 |
| 创建顺序 | 并行创建为主 | 默认按序创建 |
| 删除顺序 | 按控制器策略处理 | 默认按序号倒序删除 |
| 网络标识 | 不稳定 | 结合 Headless Service 稳定 |
| 存储关系 | 多副本通常共享模板 | 每个副本可拥有独立 PVC |
| 常见应用 | Web、API、网关 | 数据库、注册中心、协调组件 |

StatefulSet 不是为了替代 Deployment。只要应用可以做到无状态化，应优先使用 Deployment。只有当副本身份、启动顺序或数据绑定关系成为业务逻辑的一部分时，才需要 StatefulSet。

### 最小示例

下面示例创建一个名为 `web` 的 StatefulSet，并通过名为 `nginx` 的 Headless Service 提供稳定网络标识：

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  clusterIP: None
  selector:
    app: nginx
  ports:
    - name: web
      port: 80
      targetPort: 80
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web
spec:
  serviceName: nginx
  replicas: 3
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
          image: nginx:1.27
          ports:
            - name: web
              containerPort: 80
```

创建资源：

```bash
kubectl apply -f web-statefulset.yaml
kubectl get sts
kubectl get pod -l app=nginx -o wide
kubectl get svc nginx
```

`spec.serviceName` 必须指向一个已存在或即将创建的 Headless Service 名称。StatefulSet 会基于该 Service 为 Pod 生成稳定 DNS 名称。

### 核心字段

| 字段 | 说明 |
| --- | --- |
| `apiVersion` | StatefulSet 使用 `apps/v1` |
| `kind` | 资源类型，固定为 `StatefulSet` |
| `metadata.name` | StatefulSet 名称，也会作为 Pod 名称前缀 |
| `spec.serviceName` | 用于生成稳定网络标识的 Headless Service 名称 |
| `spec.replicas` | 期望副本数量，默认值为 1 |
| `spec.selector` | 匹配 StatefulSet 管理的 Pod |
| `spec.template` | Pod 模板 |
| `spec.volumeClaimTemplates` | 为每个 Pod 创建独立 PVC 的模板 |
| `spec.updateStrategy` | 更新策略，默认是 `RollingUpdate` |
| `spec.podManagementPolicy` | Pod 管理方式，默认是 `OrderedReady` |

`spec.selector.matchLabels` 必须匹配 `spec.template.metadata.labels`。创建成功后，selector 通常不能修改，因此标签需要提前规划。

### 创建顺序

StatefulSet 默认使用 `OrderedReady` 管理策略。创建多个副本时，会按序号从小到大逐个创建：

```text
web-0 -> web-1 -> web-2
```

后一个 Pod 通常需要等待前一个 Pod 进入 Ready 状态后才会创建。这个行为适合依赖顺序启动的集群组件，例如先启动第一个节点，再让其他节点加入。

观察创建过程：

```bash
kubectl get pod -l app=nginx -w
```

示例状态变化：

```text
web-0   Pending
web-0   Running
web-1   Pending
web-1   Running
web-2   Pending
web-2   Running
```

如果 `web-0` 因镜像拉取、资源不足或探针失败长时间无法 Ready，`web-1` 和 `web-2` 可能不会继续创建。排查时应先处理序号更小的 Pod。

### 独立存储

StatefulSet 的重要能力是通过 `volumeClaimTemplates` 为每个 Pod 自动创建独立 PVC：

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  serviceName: mysql
  replicas: 3
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
        - name: mysql
          image: mysql:8.0
          ports:
            - name: mysql
              containerPort: 3306
          env:
            - name: MYSQL_ROOT_PASSWORD
              value: example  # 学习环境示例；生产环境应使用 Secret: valueFrom.secretKeyRef
          volumeMounts:
            - name: data
              mountPath: /var/lib/mysql
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 10Gi
```

创建后会生成类似下面的 PVC：

```text
data-mysql-0
data-mysql-1
data-mysql-2
```

每个 PVC 与对应序号的 Pod 绑定。`mysql-1` 被删除重建后，仍会挂载 `data-mysql-1`，从而保留该副本的数据。

::: warning 注意

删除 StatefulSet 默认不会删除 `volumeClaimTemplates` 创建的 PVC。这个设计可以避免误删控制器时连带删除业务数据。清理测试环境时，需要单独确认 PVC 是否需要删除。

:::

### 常用查看命令

查看 StatefulSet：

```bash
kubectl get sts
kubectl describe sts web
kubectl get sts web -o yaml
```

查看 Pod 与 PVC：

```bash
kubectl get pod -l app=nginx -o wide
kubectl get pvc
```

查看控制器事件：

```bash
kubectl describe sts web
kubectl describe pod web-0
```

StatefulSet 排查通常从序号最小且未就绪的 Pod 开始，再检查 Headless Service、PVC、存储类和节点资源。

## Headless Service 与内部通信

StatefulSet 需要稳定的网络标识，Headless Service 正是这个能力的基础。它不分配普通 Service 的虚拟 IP，而是直接把 DNS 解析结果指向后端 Pod。

对于 StatefulSet 来说，Headless Service 不只是访问入口，更像是一组可预测的 DNS 记录。每个 Pod 都可以通过固定名称被集群内其他组件访问。

### Headless Service

普通 Service 会分配 `clusterIP`，集群内客户端访问 Service 名称时，通常会先访问这个虚拟 IP，再由 kube-proxy 转发到后端 Pod。

Headless Service 将 `clusterIP` 设置为 `None`：

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
spec:
  clusterIP: None
  selector:
    app: nginx
  ports:
    - name: web
      port: 80
      targetPort: 80
```

这种 Service 不提供统一虚拟 IP。DNS 查询会返回匹配 Pod 的地址，StatefulSet 还会为每个 Pod 生成固定 DNS 名称。

查看 Service：

```bash
kubectl get svc nginx
```

示例输出：

```text
NAME    TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
nginx   ClusterIP   None         <none>        80/TCP    1m
```

`CLUSTER-IP` 显示为 `None`，表示这是 Headless Service。

### 固定 DNS 名称

StatefulSet Pod 的完整 DNS 格式如下：

```text
<pod-name>.<service-name>.<namespace>.svc.cluster.local
```

如果 StatefulSet 名称为 `web`，Headless Service 名称为 `nginx`，Namespace 为 `default`，则 3 个 Pod 的 DNS 名称为：

```text
web-0.nginx.default.svc.cluster.local
web-1.nginx.default.svc.cluster.local
web-2.nginx.default.svc.cluster.local
```

在同一个 Namespace 中，可以使用较短名称：

```text
web-0.nginx
web-1.nginx
web-2.nginx
```

这些名称与 Pod 序号绑定。即使 `web-1` 被删除重建，新的 `web-1` 仍然使用同一个 DNS 名称。

### 通信验证

创建一个临时调试 Pod：

```bash
kubectl run dns-test --image=busybox:1.36.1 --restart=Never -- sleep 3600
```

进入容器后查询 DNS：

```bash
kubectl exec -it dns-test -- sh
nslookup web-0.nginx
nslookup web-1.nginx.default.svc.cluster.local
```

也可以直接访问指定副本：

```bash
kubectl exec -it dns-test -- wget -qO- web-0.nginx
kubectl exec -it dns-test -- wget -qO- web-1.nginx
```

从 StatefulSet 的某个 Pod 访问另一个 Pod：

```bash
kubectl exec -it web-2 -- curl web-1.nginx
```

跨 Namespace 访问时，需要带上目标 Namespace：

```bash
kubectl exec -it web-2 -- curl web-1.nginx.default
```

如果当前容器镜像没有 `curl`，可以换用 `wget` 或创建带调试工具的临时 Pod。

### 解析关系

StatefulSet、Headless Service 和 Pod 的关系可以概括为：

```text
StatefulSet -> Pod: web-0, web-1, web-2
Headless Service -> EndpointSlice: Pod IP 列表
CoreDNS -> 固定 DNS 名称: web-0.nginx
```

排查内部通信时，应同时查看 Service、EndpointSlice 和 Pod 标签：

```bash
kubectl get svc nginx -o yaml
kubectl get endpointslices -l kubernetes.io/service-name=nginx
kubectl get pod -l app=nginx --show-labels
```

如果 Service 的 selector 与 Pod 标签不匹配，EndpointSlice 中不会出现后端地址，DNS 解析也无法得到预期结果。

### 常见问题

| 现象 | 可能原因 | 排查命令 |
| --- | --- | --- |
| `nslookup web-0.nginx` 失败 | CoreDNS 异常或名称写错 | `kubectl get pod -n kube-system -l k8s-app=kube-dns` |
| Service 没有后端地址 | selector 与 Pod 标签不匹配 | `kubectl get endpointslices -l kubernetes.io/service-name=nginx` |
| 只能解析 Service，不能解析单个 Pod | StatefulSet 未配置正确 `serviceName` | `kubectl get sts web -o yaml` |
| 可以解析但访问失败 | 容器端口、应用监听或网络策略问题 | `kubectl describe pod web-0` |
| 访问旧 IP | DNS 缓存或 Pod 尚未 Ready | `kubectl get pod -o wide` |

Headless Service 的关键是标签匹配和 DNS 记录。先确认 Pod Ready，再确认 Service selector，最后确认 DNS 查询结果，通常可以快速定位问题。

### Eureka 集群示例

Eureka 这类注册中心需要节点之间互相发现。使用 StatefulSet 可以让每个副本拥有固定名称，再把这些固定名称写入对等节点地址。该示例用于说明固定 DNS 对自组集群的价值，不表示所有 Kubernetes 应用都需要额外引入注册中心。

下面示例只展示 StatefulSet 与 Headless Service 的组织方式，实际生产还需要补充镜像、探针、资源限制和配置管理：

```yaml
apiVersion: v1
kind: Service
metadata:
  name: eureka
spec:
  clusterIP: None
  selector:
    app: eureka
  ports:
    - name: http
      port: 8761
      targetPort: 8761
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: eureka
spec:
  serviceName: eureka
  replicas: 3
  selector:
    matchLabels:
      app: eureka
  template:
    metadata:
      labels:
        app: eureka
    spec:
      containers:
        - name: eureka
          image: <registry.example.com>/<namespace>/eureka:1.0.0
          ports:
            - name: http
              containerPort: 8761
          env:
            - name: EUREKA_INSTANCE_HOSTNAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: EUREKA_PEERS
              value: "http://eureka-0.eureka:8761/eureka/,http://eureka-1.eureka:8761/eureka/,http://eureka-2.eureka:8761/eureka/"
```

这里的关键不是具体镜像，而是 `eureka-0.eureka`、`eureka-1.eureka`、`eureka-2.eureka` 这些稳定地址。应用可以把它们作为集群成员列表，从而避免 Pod 重建后名称变化导致节点发现失败。

::: tip 提示

对于真实业务配置，建议将成员列表放入 ConfigMap 或启动参数模板中，不要把环境差异直接写死在工作负载 YAML 中。

:::

## StatefulSet 更新扩缩容

StatefulSet 的扩缩容和更新都围绕 Pod 序号进行。默认情况下，扩容按序号正序创建，缩容按序号倒序删除，更新则从最大序号开始逐个替换。

这种行为看起来比 Deployment 慢，但它能为有状态组件提供更可控的变更顺序。对于依赖成员关系、数据副本或选主机制的应用，顺序往往比速度更重要。

### 扩容与缩容

创建示例 StatefulSet 后，可以通过 `kubectl scale` 调整副本数：

```bash
kubectl scale sts web --replicas=5
kubectl get pod -l app=nginx -w
```

扩容时，StatefulSet 默认按序号正序创建新 Pod：

```text
web-3 -> web-4
```

缩容到 2 个副本：

```bash
kubectl scale sts web --replicas=2
kubectl get pod -l app=nginx -w
```

缩容时，StatefulSet 默认按序号倒序删除 Pod：

```text
web-4 -> web-3 -> web-2
```

也可以修改 YAML 中的 `spec.replicas` 后执行：

```bash
kubectl apply -f web-statefulset.yaml
```

生产中更推荐通过 YAML 或发布平台管理副本数量，避免命令式操作造成配置漂移。

### 缩容注意事项

StatefulSet 缩容会删除高序号 Pod，但通常不会自动删除对应 PVC。以 `web` 为例，缩容前后可能出现：

```text
web-0
web-1
data-web-0
data-web-1
data-web-2
```

即使 `web-2` 已被删除，`data-web-2` 仍可能保留。之后重新扩容到 3 个副本时，新的 `web-2` 可以继续使用原来的 PVC。

缩容有状态应用前应确认：

- 高序号节点是否已经从业务集群中安全移除
- 数据副本是否已经完成迁移或同步
- 客户端、注册中心或成员列表是否已经感知节点减少
- PVC 是否需要保留以便后续恢复

测试环境中如果确实要清理 PVC，可以单独删除：

```bash
kubectl delete pvc data-web-2
```

生产环境删除 PVC 前必须确认数据已经备份或不再需要。

### 更新策略

StatefulSet 通过 `spec.updateStrategy` 控制更新方式：

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: rolling-web
spec:
  serviceName: rolling-web
  replicas: 3
  updateStrategy:
    type: RollingUpdate
  selector:
    matchLabels:
      app: rolling-web
  template:
    metadata:
      labels:
        app: rolling-web
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
```

常见策略如下：

| 策略 | 行为 | 适用场景 |
| --- | --- | --- |
| `RollingUpdate` | Pod 模板变化后自动滚动更新 | 大多数 StatefulSet |
| `OnDelete` | 模板变化后不自动更新，手动删除 Pod 才重建 | 需要人工确认每个节点更新的场景 |

Kubernetes 当前默认使用 `RollingUpdate`。更新镜像示例：

```bash
kubectl set image sts web nginx=nginx:1.26
kubectl rollout status sts web
```

更新过程默认从最大序号开始：

```text
web-2 -> web-1 -> web-0
```

每个 Pod 会先删除旧实例，再创建新实例。新 Pod Ready 后，才继续处理下一个序号。

### 分段更新

`partition` 可以让 StatefulSet 只更新部分高序号 Pod，常用于灰度发布：

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: partition-web
spec:
  serviceName: partition-web
  replicas: 5
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 3
  selector:
    matchLabels:
      app: partition-web
  template:
    metadata:
      labels:
        app: partition-web
    spec:
      containers:
        - name: nginx
          image: nginx:1.26
```

假设 StatefulSet 有 5 个副本：

```text
web-0
web-1
web-2
web-3
web-4
```

当 `partition: 3` 时，只有序号大于等于 3 的 Pod 会更新：

```text
web-3
web-4
```

低序号 Pod 会继续运行旧版本：

```text
web-0
web-1
web-2
```

修改 `partition`：

```bash
kubectl patch sts web -p '{"spec":{"updateStrategy":{"type":"RollingUpdate","rollingUpdate":{"partition":3}}}}'
kubectl set image sts web nginx=nginx:1.26
kubectl rollout status sts web
```

观察镜像版本：

```bash
kubectl get pod -l app=nginx -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
```

确认高序号 Pod 运行正常后，可以逐步降低 partition：

```bash
kubectl patch sts web -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":2}}}}'
kubectl patch sts web -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":1}}}}'
kubectl patch sts web -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":0}}}}'
```

`partition: 0` 表示所有 Pod 都应更新到新版本。

### OnDelete 策略

`OnDelete` 策略不会在 Pod 模板变化后自动替换 Pod：

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ondelete-web
spec:
  serviceName: ondelete-web
  replicas: 3
  updateStrategy:
    type: OnDelete
  selector:
    matchLabels:
      app: ondelete-web
  template:
    metadata:
      labels:
        app: ondelete-web
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
```

修改镜像后，已有 Pod 仍会继续运行旧版本。只有手动删除某个 Pod 后，StatefulSet 才会按新模板创建替代 Pod：

```bash
kubectl set image sts web nginx=nginx:1.26
kubectl delete pod web-2
kubectl get pod web-2 -w
```

这种方式适合强依赖人工确认的组件，例如每更新一个节点都需要先确认集群状态、数据同步状态或业务指标。

### 回滚与版本管理

StatefulSet 支持查看发布历史和回滚：

```bash
kubectl rollout history sts web
kubectl rollout undo sts web
kubectl rollout status sts web
```

回滚到指定 revision：

```bash
kubectl rollout undo sts web --to-revision=2
kubectl rollout status sts web
```

与 Deployment 类似，回滚只针对 Pod 模板历史，不会回滚 PVC、外部数据库、ConfigMap 或 Secret。对于有状态应用，回滚前还需要额外确认数据格式和协议兼容性。

查看 StatefulSet 更新策略：

```bash
kubectl get sts web -o yaml | grep -A 4 "updateStrategy"
```

查看当前镜像：

```bash
kubectl describe pod web-0 | grep Image:
```

### 并发管理 Pod

StatefulSet 默认的 Pod 管理策略是 `OrderedReady`：

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ordered-web
spec:
  serviceName: ordered-web
  replicas: 3
  podManagementPolicy: OrderedReady
  selector:
    matchLabels:
      app: ordered-web
  template:
    metadata:
      labels:
        app: ordered-web
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
```

它会按顺序创建、删除和扩缩容 Pod。也可以改为 `Parallel`：

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: parallel-web
spec:
  serviceName: parallel-web
  replicas: 3
  podManagementPolicy: Parallel
  selector:
    matchLabels:
      app: parallel-web
  template:
    metadata:
      labels:
        app: parallel-web
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
```

两种策略对比如下：

| 策略 | 行为 | 适用场景 |
| --- | --- | --- |
| `OrderedReady` | 按序号顺序创建和删除，等待前一个 Ready | 需要有序启动或有序退场的应用 |
| `Parallel` | 并行创建和删除 Pod | 副本之间没有启动顺序依赖的应用 |

`podManagementPolicy` 主要影响扩缩容过程，不会改变滚动更新时按序号倒序更新的基本行为。

::: warning 注意

`podManagementPolicy` 创建后通常不应随意调整。选择 `Parallel` 前，需要确认应用不依赖固定启动顺序，也不要求前一个成员 Ready 后再加入下一个成员。

:::

### 删除 StatefulSet

删除 StatefulSet：

```bash
kubectl delete sts web
```

默认会删除 StatefulSet 管理的 Pod，但 PVC 通常会保留。如果只想删除控制器并保留 Pod，可以使用非级联删除：

```bash
kubectl delete sts web --cascade=orphan
```

保留 Pod 的场景较少，通常用于特殊迁移或接管操作。普通清理环境时，更常见的是删除 StatefulSet、确认 Pod 消失，再按需处理 Service 和 PVC。

```bash
kubectl delete svc nginx
kubectl get pvc
```

有状态资源的清理顺序需要谨慎，尤其不能把删除控制器等同于删除数据。
