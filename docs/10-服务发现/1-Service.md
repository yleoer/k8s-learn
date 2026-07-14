# Service

Service 是 Kubernetes 为后端 Pod 或其他网络端点提供稳定访问入口的核心资源。Service 通过固定名称、固定虚拟 IP 或固定端口屏蔽后端端点变化，调用方不需要直接维护 Pod IP 或外部地址列表。

本文集中记录 Service 资源定义、Service 类型、流量策略、双栈地址族、多端口、会话保持、EndpointSlice 与 Endpoints 兼容、DNS、Headless Service、代理模式和排查记录。Ingress、Gateway API 和 Traefik 在后续独立文档中记录。

## Service 定义与访问

Service 的基础配置集中在 `metadata.name`、`spec.selector`、`spec.ports` 和 `spec.type`。其中 `metadata.name` 会参与集群内 DNS 名称生成，`selector` 决定后端 Pod 范围，`ports` 决定 Service 暴露端口与后端端口的映射关系。

### 创建与查看

复用本章入口[工作负载关系](./index.md#工作负载关系)中的完整 `run-my-nginx.yaml` 创建 Deployment，再通过 `kubectl expose` 生成 Service：

```bash
kubectl create -f run-my-nginx.yaml
kubectl expose deploy/my-nginx
kubectl get svc my-nginx
kubectl describe svc my-nginx
kubectl get eplices -l kubernetes.io/service-name=my-nginx
```

`kubectl expose` 会查找指定 Deployment、Service、ReplicaSet、ReplicationController 或 Pod，并使用该资源的 selector 为新 Service 生成 selector。长期维护时仍建议保存 Service YAML，并通过声明式方式管理。

### 基础字段

| 字段                         | 是否必选   | 说明                                                                     |
|----------------------------|--------|------------------------------------------------------------------------|
| `apiVersion`               | 是      | Service 使用 `v1`                                                        |
| `kind`                     | 是      | 资源类型，固定为 `Service`                                                     |
| `metadata.name`            | 是      | Service 名称，同一 Namespace 内唯一，也会成为 DNS 名称的一部分                            |
| `spec.selector`            | 否      | 用于选择后端 Pod；ExternalName 不使用该字段；无 selector Service 不会自动生成 EndpointSlice |
| `spec.ports`               | 视类型而定  | Service 暴露端口列表；ExternalName 可以不定义端口                                    |
| `spec.ports[].name`        | 多端口时必选 | 端口名称，同一个 Service 内需要唯一                                                 |
| `spec.ports[].port`        | 是      | Service 自身暴露的端口                                                        |
| `spec.ports[].targetPort`  | 否      | 后端端口，未配置时默认等于 `port`                                                   |
| `spec.ports[].protocol`    | 否      | 协议，默认 `TCP`，也可使用 `UDP`、`SCTP`                                          |
| `spec.ports[].appProtocol` | 否      | 应用协议提示，会镜像到对应 EndpointSlice                                            |
| `spec.type`                | 否      | Service 类型，默认 `ClusterIP`                                              |
| `spec.sessionAffinity`     | 否      | 会话保持配置，默认 `None`                                                       |

查看字段说明：

```bash
kubectl explain svc.spec
kubectl explain svc.spec.ports
```

### 端口映射

Service 端口与后端 Pod 端口可以不同。端口命名示例如下：

```yaml{8-12,24-26} [nginx-service-and-pod.yaml]
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    app.kubernetes.io/name: proxy
  ports:
    - name: name-of-service-port
      protocol: TCP
      port: 80
      targetPort: http-web-svc
---
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  labels:
    app.kubernetes.io/name: proxy
spec:
  containers:
    - name: nginx
      image: nginx:1.31-alpine
      ports:
        - containerPort: 80
          name: http-web-svc
```

这里 `targetPort: http-web-svc` 引用了 Pod 中定义的容器端口名。端口名可以降低 Service 与容器端口号之间的耦合，但需要保证端口名在 Pod 模板中真实存在。

## Service 类型

Service 通过 `spec.type` 决定暴露方式。常见类型包括 `ClusterIP`、`NodePort`、`LoadBalancer` 和 `ExternalName`。

| 类型             | 访问范围              | 典型用途                     |
|----------------|-------------------|--------------------------|
| `ClusterIP`    | 集群内部              | 服务间访问，默认类型               |
| `NodePort`     | 节点 IP 加固定端口       | 简单暴露集群内服务，常用于实验或对接外部负载均衡 |
| `LoadBalancer` | 云厂商或负载均衡实现提供的外部地址 | 云环境对外发布四层服务              |
| `ExternalName` | DNS CNAME 别名      | 在集群内用 Service 名称引用外部域名   |

`NodePort` 和 `LoadBalancer` 都建立在 `ClusterIP` 能力之上。`ExternalName` 不会创建普通代理规则，也不转发到 Pod。

### ClusterIP

`ClusterIP` 是默认类型。Kubernetes 会为 Service 分配一个集群内部虚拟 IP，客户端通过 Service 名称或 ClusterIP 访问后端 Pod。

本章入口[工作负载关系](./index.md#工作负载关系)中的完整 `nginx-svc.yaml` 未显式声明 `spec.type`，因此会创建为 `ClusterIP`，此处不重复清单。

ClusterIP 通常只在集群内可达。集群外访问业务服务时，应根据环境选择 Ingress、Gateway API、LoadBalancer 或 NodePort。

### NodePort

`NodePort` 会在每个运行 kube-proxy 的节点上打开一个端口，并把该端口的流量转发到 Service 后端。访问形式通常是：

```text
<node-ip>:<node-port>
```

以下 Service 片段用于说明 NodePort 与多端口字段关系；完整应用清单还需要包含对应后端工作负载：

```yaml{8-16} [my-nginx-nodeport.yaml]
apiVersion: v1
kind: Service
metadata:
  name: my-nginx
  labels:
    run: my-nginx
spec:
  type: NodePort
  ports:
    - port: 8080
      targetPort: 80
      protocol: TCP
      name: http
    - port: 443
      protocol: TCP
      name: https
  selector:
    run: my-nginx
```

如果不指定 `nodePort`，Kubernetes 会从 apiserver 的 `--service-node-port-range` 范围内自动分配端口。默认范围通常是 `30000-32767`。

使用 NodePort 时需要注意：

- 手动指定的 `nodePort` 必须处于允许范围内且未被占用
- 节点防火墙、安全组或云厂商网络策略需要放行该端口
- NodePort 暴露的是节点端口，不适合直接作为复杂 HTTP 路由入口
- 生产环境常见做法是在 NodePort 前再接入外部负载均衡器

不同 kube-proxy 模式对 NodePort 监听地址的细节可能不同，尤其是从 iptables 迁移到 nftables 时，需要关注 `nodePortAddresses` 等配置差异。

### LoadBalancer

`LoadBalancer` 用于请求底层环境创建外部负载均衡器。云厂商 Kubernetes 或安装了负载均衡实现的裸金属集群，通常会为该 Service 分配外部 IP 或主机名。

沿用 `my-nginx` 示例时，可以通过编辑 Service 将类型从 `NodePort` 改为 `LoadBalancer`：

```bash
kubectl edit svc my-nginx
kubectl get svc my-nginx
kubectl describe svc my-nginx
```

如果 `EXTERNAL-IP` 长时间处于 `pending`，通常说明当前集群没有可用的 LoadBalancer 实现。裸金属环境可以结合 MetalLB、kube-vip 或云厂商提供的控制器来实现。

`LoadBalancer` 相关字段需要特别区分：

| 字段                                   | 说明                                                         |
|--------------------------------------|------------------------------------------------------------|
| `spec.loadBalancerClass`             | 指定非默认负载均衡实现，只能用于 `LoadBalancer` 类型，设置后不可变                  |
| `spec.allocateLoadBalancerNodePorts` | 默认为 `true`；支持直连 Pod 的负载均衡实现可以设置为 `false`                   |
| `spec.loadBalancerIP`                | v1.24 起 deprecated，语义在不同实现中不一致，也无法支持双栈；应改用实现特定的 annotation |

`LoadBalancer` 适合暴露少量四层服务。HTTP、HTTPS 多域名和路径路由更常放在 Ingress 或 Gateway API 中统一管理。

### ExternalName

`ExternalName` 通过 DNS CNAME 把 Service 名称映射到外部域名。它不创建 ClusterIP，也不通过 kube-proxy 转发流量。

下面示例把 `prod` Namespace 中的 `my-service` 映射到 `my.database.example.com`：

```yaml{7,8} [external-name-service.yaml]
apiVersion: v1
kind: Service
metadata:
  name: my-service
  namespace: prod
spec:
  type: ExternalName
  externalName: my.database.example.com
```

查询 `my-service.prod.svc.cluster.local` 时，集群 DNS 会返回指向 `my.database.example.com` 的 CNAME 记录。连接是否成功取决于外部 DNS、网络路由、防火墙和目标服务自身。

使用 ExternalName 时需要注意协议行为。HTTP 客户端访问 Service 名称时，请求中的 `Host` 可能仍是 Service 名称，而不是目标外部域名；TLS 服务也可能因为客户端连接名与证书名称不一致而失败。

### externalIPs

`spec.externalIPs` 表示由集群管理员负责路由到节点的外部 IP。Kubernetes 不负责分配这些 IP，也不负责外部网络路由。

Kubernetes v1.36 起 `externalIPs` 已正式弃用，底层原因与 CVE-2020-8554 等安全问题相关。官方给出的时间线为：v1.36 发出弃用警告并通过 `AllowServiceExternalIPs` feature gate（默认 `true`）保留功能；v1.40 起该 feature gate 默认为 `false`，kube-proxy 不再为 externalIPs 生成转发规则；最早在 v1.43 完全移除代码支持。已有集群应尽早规划迁移到 LoadBalancer、MetalLB、kube-vip 或 Gateway API。

## 流量策略与拓扑

Service 流量策略用于控制 kube-proxy 或替代数据面对就绪端点的选择方式。它们不是应用层路由规则，而是 Service 数据面选择端点时的约束或偏好。

### 流量策略

| 字段                           | 可选值               | 行为                                                |
|------------------------------|-------------------|---------------------------------------------------|
| `spec.internalTrafficPolicy` | `Cluster`、`Local` | 控制集群内部来源流量；`Cluster` 使用所有就绪端点，`Local` 只使用节点本地就绪端点 |
| `spec.externalTrafficPolicy` | `Cluster`、`Local` | 控制外部来源流量；`Cluster` 使用所有就绪端点，`Local` 只使用节点本地就绪端点   |

`Cluster` 是默认行为。`Local` 提供更强的本地性约束：如果当前节点没有本地就绪端点，对应流量不会被转发到其他节点。`externalTrafficPolicy: Local` 常用于保留客户端源 IP，但需要配合负载均衡健康检查、Pod 分布和滚动更新策略评估可用性。

### 流量分布

`spec.trafficDistribution` 用于表达端点选择偏好。它不同于 `internalTrafficPolicy` 和 `externalTrafficPolicy` 的强约束，更适合表达拓扑接近性：

| 值                | 含义                                                                    |
|------------------|-----------------------------------------------------------------------|
| `PreferSameZone` | 优先选择与客户端处于同一 zone 的端点                                                 |
| `PreferSameNode` | 优先选择与客户端处于同一节点的端点                                                     |
| `PreferClose`    | `PreferSameZone` 的旧别名，已标记为 deprecated，语义不如新名称清晰；建议改用 `PreferSameZone` |

未设置 `trafficDistribution` 时，默认策略是在集群内所有端点之间分布流量。若对应流量类型的 `internalTrafficPolicy` 或 `externalTrafficPolicy` 设置为 `Local`，该强约束优先于 `trafficDistribution`。

EndpointSlice 可以携带 `hints`、`zone`、`nodeName` 等信息，供支持拓扑感知的实现使用。旧的 `service.kubernetes.io/topology-mode: Auto` 注解目前仍然有效，且设置后优先于 `trafficDistribution` 生效；官方计划未来用 `trafficDistribution` 取代该注解，新配置应直接使用 `trafficDistribution`。

## 双栈与地址族

Kubernetes 支持 IPv4 单栈、IPv6 单栈以及 IPv4/IPv6 双栈 Service。双栈是否可用取决于集群网络插件、控制面参数、节点网络和负载均衡实现。

Service 地址族相关字段如下：

| 字段                    | 说明                        |
|-----------------------|---------------------------|
| `spec.ipFamilyPolicy` | 控制单栈或双栈分配策略               |
| `spec.ipFamilies`     | 指定地址族以及双栈时的顺序             |
| `spec.clusterIPs`     | 记录实际分配的一个或两个 ClusterIP    |
| `spec.clusterIP`      | 旧字段，取自 `clusterIPs` 的第一个值 |

`ipFamilyPolicy` 的常见取值：

| 值                  | 行为                            |
|--------------------|-------------------------------|
| `SingleStack`      | 分配单个地址族的 ClusterIP            |
| `PreferDualStack`  | 双栈可用时分配 IPv4 和 IPv6；不可用时回退到单栈 |
| `RequireDualStack` | 要求分配 IPv4 和 IPv6；双栈不可用时创建失败   |

显式请求双栈可以写为：

```yaml{8} [dual-stack-service.yaml]
apiVersion: v1
kind: Service
metadata:
  name: my-service
  labels:
    app.kubernetes.io/name: MyApp
spec:
  ipFamilyPolicy: PreferDualStack
  selector:
    app.kubernetes.io/name: MyApp
  ports:
    - protocol: TCP
      port: 80
```

如果需要指定地址族顺序，可以设置 `ipFamilies`。第一个地址族会决定旧字段 `spec.clusterIP` 的地址族：

```yaml{8-11} [dual-stack-service-ip-families.yaml]
apiVersion: v1
kind: Service
metadata:
  name: my-service
  labels:
    app.kubernetes.io/name: MyApp
spec:
  ipFamilyPolicy: PreferDualStack
  ipFamilies:
    - IPv6
    - IPv4
  selector:
    app.kubernetes.io/name: MyApp
  ports:
    - protocol: TCP
      port: 80
```

`ipFamilies` 的主地址族不能在已有 Service 上随意改变。已有单栈 Service 切换为双栈时，应通过 `ipFamilyPolicy` 增加缺失地址族，并确认集群和负载均衡实现支持对应地址族。

## 多端口与会话保持

一个 Service 可以同时暴露多个端口，适合一个后端 Pod 提供多个协议或管理端口的场景。多端口 Service 中，每个端口都必须设置唯一名称。

### 多端口 Service

多端口 Service 示例：

```yaml{8-16} [multi-port-service.yaml]
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  selector:
    app.kubernetes.io/name: MyApp
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 9376
    - name: https
      protocol: TCP
      port: 443
      targetPort: 9377
```

多端口 Service 适合端口属于同一个后端实例的情况。如果两个端口对应不同发布节奏、不同副本规模或不同安全边界，应拆分为不同工作负载和 Service。

### 会话保持

Service 默认不保证同一个客户端始终访问同一个后端 Pod。对于需要粘性会话的场景，可以配置基于客户端 IP 的会话保持。

| 字段                                              | 说明                  |
|-------------------------------------------------|---------------------|
| `sessionAffinity: None`                         | 默认值，不启用会话保持         |
| `sessionAffinity: ClientIP`                     | 按客户端 IP 做会话保持       |
| `sessionAffinityConfig.clientIP.timeoutSeconds` | 粘性会话保持时间，默认 10800 秒 |

会话保持适合短期兼容依赖本地会话的应用。长期看，更推荐把会话状态放到共享存储、缓存或数据库中，让任意副本都可以处理请求。

需要注意，客户端 IP 可能经过 NAT、代理或网关改写。大量客户端共享同一个源 IP 时，`ClientIP` 可能导致流量集中到少数 Pod。

## EndpointSlice

Service 本身记录的是访问抽象，后端真实地址由 EndpointSlice 表示。EndpointSlice 会保存一组后端端点的 IP、端口、协议、就绪状态、所在节点和拓扑信息，供 kube-proxy、DNS 和其他控制器消费。默认情况下，控制面维护的每个 EndpointSlice 最多包含 100 个端点，端点数量超过上限时会自动创建新的分片；该上限可通过 kube-controller-manager 的 `--max-endpoints-per-slice` 参数调整，最大值为 1000。因此一个 Service 可能对应多个 EndpointSlice，查询时应按 `kubernetes.io/service-name` 标签列出，而不是按名称获取。

早期 Kubernetes 使用 Endpoints 资源记录后端地址。当前主线中，EndpointSlice 是更推荐关注的后端端点 API；Endpoints API 已在 v1.33 被标记为 deprecated。

### 自动维护过程

对于带 selector 的 Service，控制器会根据匹配 Pod 自动维护 EndpointSlice：

| 步骤 | 行为                                       |
|----|------------------------------------------|
| 1  | 创建 Service，配置 `spec.selector`            |
| 2  | 控制器查找标签匹配的 Pod                           |
| 3  | 控制器为 Service 创建或更新 EndpointSlice         |
| 4  | kube-proxy 监听 Service 和 EndpointSlice 变化 |
| 5  | 节点上的代理规则更新，流量可以转发到就绪端点                   |

查看 Service 与 EndpointSlice：

```bash
kubectl get svc my-nginx
kubectl get eplices -l kubernetes.io/service-name=my-nginx
kubectl describe eplices -l kubernetes.io/service-name=my-nginx
```

排查旧组件或兼容性问题时，也可以查看 Endpoints：

```bash
kubectl get ep my-nginx
```

Kubernetes v1.33 起，该命令会额外输出一条 Endpoints 弃用警告，属于预期行为，详见下文「Endpoints 兼容」。

如果 Service 可以解析但访问失败，应同时查看 Pod readiness 状态和 EndpointSlice 内容：

```bash
kubectl get po -l run=my-nginx -o wide
kubectl get eplices -l kubernetes.io/service-name=my-nginx -o yaml
kubectl describe svc my-nginx
```

EndpointSlice 中每个端点有三种状态条件：`conditions.serving` 表示端点正在提供服务（对应 Pod 的 Ready 状态）；`conditions.terminating` 表示端点正在终止中（Pod 已收到删除时间戳）；`conditions.ready` 是 `serving && !terminating` 的快捷表达，常用于兼容性查询。对于 Pod 后端，控制器根据 Pod Ready 状态、终止状态以及 Service 的 `publishNotReadyAddresses` 配置计算这些条件。Pod 未 Ready、selector 不匹配、端口名写错，都可能导致 Service 没有可用后端。

### 无 selector Service

Service 可以不配置 selector，此时 Kubernetes 不会自动创建后端端点。需要手动创建 EndpointSlice，把 Service 名称与端点关联起来。

这种方式常用于在集群内用固定 Service 名称访问外部系统，例如迁移期间仍运行在集群外的数据库、缓存或旧服务。

下面清单展示无 selector Service 与手动 EndpointSlice 的对应关系，并使用 `endpointslice.kubernetes.io/managed-by` 标识维护方：

```yaml [external-backend-service.yaml]
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 9376
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: my-service-1
  labels:
    kubernetes.io/service-name: my-service
    endpointslice.kubernetes.io/managed-by: cluster-admins
addressType: IPv4
ports:
  - name: http
    appProtocol: http
    protocol: TCP
    port: 9376
endpoints:
  - addresses:
      - "10.4.5.6"
  - addresses:
      - "10.1.2.3"
```

手动维护 EndpointSlice 时需要注意：

- `kubernetes.io/service-name` 标签必须指向对应 Service 名称
- `endpointslice.kubernetes.io/managed-by` 标签应标识维护该 EndpointSlice 的控制器或管理方
- EndpointSlice 的端口名称应与 Service 端口名称一致，端口号应对应后端实际端口
- Endpoint IP 不能是 loopback、link-local 或其他 Service 的 ClusterIP
- 外部 IP 不由 Kubernetes 管理，故障摘除和地址变更需要额外机制维护

### Endpoints 兼容

Endpoints API 是 EndpointSlice API 的前身。Kubernetes v1.33 起，Endpoints API 被标记为 deprecated；它不支持双栈集群，缺少流量分布等新功能所需信息，且单个对象超过 1000 个后端端点时会截断。

新配置应优先使用 EndpointSlice。`kubectl get ep` 主要用于兼容性观察、识别旧写法或排查仍依赖 Endpoints 的旧组件。Endpoints 对理解 Service 与后端的关联仍有学习价值：旧集群、旧脚本和不少存量工具的输出仍围绕 Endpoints 组织，排查这类环境时需要能同时读懂两种对象。

两个 API 的职责边界与对象模型不同：

| 对比项              | Endpoints                          | EndpointSlice                             |
|------------------|------------------------------------|-------------------------------------------|
| API 版本           | `v1`（core 组）                      | `discovery.k8s.io/v1`                     |
| 与 Service 的对应关系 | 带 selector 的 Service 恰好对应一个同名对象   | 一个 Service 对应一个或多个对象，名称不可预测            |
| 查询方式             | 按 Service 同名获取                    | 按 `kubernetes.io/service-name` 标签列出       |
| 双栈支持             | 不支持，只展示主地址族端点                    | 支持，IPv4 与 IPv6 分属不同 EndpointSlice         |
| 容量限制             | 单对象最多 1000 个端点，超出截断              | 默认每片最多 100 个端点，超出自动新建分片                |
| 当前状态             | v1.33 起 deprecated，读写返回弃用警告       | 当前主线端点 API                               |

Kubernetes v1.33 起，通过 API 读写 Endpoints 资源时，API server 会返回弃用警告，kubectl 会把警告打印出来。官方博客给出的示例输出如下：

```text
$ kubectl get ep myservice
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME        ENDPOINTS         AGE
myservice   10.180.3.17:443   1h
```

> [!NOTE]
> 该警告不影响命令结果，排查旧集群或旧组件时看到它属于预期行为；但如果自动化脚本会解析命令的标准错误输出，需要提前处理这条警告。

Endpoints 的截断行为需要单独理解：后端端点超过 1000 时，控制面只在 Endpoints 对象中保留至多 1000 个端点，并为对象添加 `endpoints.kubernetes.io/over-capacity: truncated` 注解；端点数量降回 1000 以内后，控制面会移除该注解。仍依赖 Endpoints 的负载均衡组件此时最多只能看到 1000 个后端，这是大规模 Service 必须迁移到 EndpointSlice 的直接原因之一。EndpointSlice 没有这个总量限制，超过单片上限时会自动拆分为多个分片。

排查旧集群或阅读旧清单时，还需要认识 Endpoints 的 `subsets` 结构。下面片段仅用于说明 Endpoints 与 EndpointSlice 的字段对应关系，新配置不应再使用这种写法：

```yaml{5-12}
apiVersion: v1
kind: Endpoints
metadata:
  name: my-service
subsets:
  - addresses:
      - ip: 10.4.5.6
      - ip: 10.1.2.3
    ports:
      - name: http
        protocol: TCP
        port: 9376
```

与前文手动 EndpointSlice 清单对照：Endpoints 通过与 Service 同名建立关联，用 `subsets` 数组表达端点，`addresses` 与 `notReadyAddresses` 分别表示就绪与未就绪端点；EndpointSlice 通过 `kubernetes.io/service-name` 标签关联 Service，需要显式声明 `addressType`，每个端点用 `conditions` 表达就绪状态。一个包含多个 subset 或同时包含 IPv4、IPv6 地址的 Endpoints，对应到 EndpointSlice 时会拆分为多个对象。

对于无 selector Service，旧做法是手工维护同名 Endpoints。为兼容旧组件，控制面默认仍会把用户创建的 Endpoints 镜像为对应的 EndpointSlice（每个 subset 最多镜像 1000 个地址；带 `endpointslice.kubernetes.io/skip-mirror: true` 标签、对应 Service 不存在或 Service 带非空 selector 等情况除外）。该镜像机制随 Endpoints API 一起弃用，手工维护后端应直接创建 EndpointSlice，写法见前文无 selector Service 示例。

## 协议与 DNS

Service 既提供虚拟 IP，也会被集群 DNS 暴露为稳定名称。对于集群内客户端，DNS 通常比环境变量更适合作为服务发现入口。

### 应用协议

`spec.ports[].protocol` 表示传输层协议，默认值为 `TCP`，也可以使用 `UDP` 或 `SCTP`。`spec.ports[].appProtocol` 表示应用协议提示，供实现方对已知协议提供更丰富行为；该字段会镜像到对应的 Endpoints 和 EndpointSlice 对象。

`appProtocol` 可以使用 IANA 标准服务名、带前缀的实现自定义名称，也可以使用 Kubernetes 预定义值，例如 `kubernetes.io/h2c`、`kubernetes.io/ws`、`kubernetes.io/wss`。

### DNS 记录

普通 Service 会获得 A 或 AAAA 记录，名称形式如下：

```text
<service-name>.<namespace>.svc.<cluster-domain>
```

在多数集群中，默认集群域为 `cluster.local`。同 Namespace 内的 Pod 可以直接使用 Service 名称；跨 Namespace 访问时需要补充 Namespace，例如：

```text
my-service.my-ns
my-service.my-ns.svc.cluster.local
```

普通 Service 的 A 或 AAAA 记录解析到 Service 的 ClusterIP。Headless Service 也会获得 A 或 AAAA 记录，但解析结果是后端端点地址集合。

对于具名端口，Kubernetes DNS 会创建 SRV 记录：

```text
_<port-name>._<port-protocol>.<service-name>.<namespace>.svc.<cluster-domain>
```

例如端口名为 `http`、协议为 `TCP` 的 Service，可以查询：

```text
_http._tcp.my-service.my-ns
```

ExternalName Service 只能通过 DNS 访问，集群 DNS 会为它返回 CNAME 记录。

### 环境变量发现

kubelet 会为 Pod 注入创建 Pod 时已经存在的 Service 环境变量，例如 `{SVCNAME}_SERVICE_HOST` 和 `{SVCNAME}_SERVICE_PORT`。如果 Service 在客户端 Pod 之后创建，已有 Pod 不会自动获得对应环境变量。

只使用 DNS 发现 Service 时，不需要关心这种创建顺序。若应用不希望注入 Service 环境变量，可以在 Pod spec 中设置 `enableServiceLinks: false`。

## Headless Service

Headless Service 不分配 ClusterIP，DNS 会直接返回后端端点地址。

### 工作方式

Headless Service 是不分配 ClusterIP 的 Service，配置方式是 `clusterIP: None`。它不提供普通 Service 的虚拟 IP，DNS 会直接返回后端端点地址。

普通 Service 与 Headless Service 的核心区别如下：

| 对比项       | 普通 Service           | Headless Service           |
|-----------|----------------------|----------------------------|
| ClusterIP | 分配虚拟 IP              | `None`                     |
| DNS 结果    | Service ClusterIP    | 后端端点 IP 集合                 |
| 代理转发      | 通常经过 kube-proxy 代理规则 | 客户端直接连接解析到的端点              |
| 常见用途      | 无状态服务统一入口            | StatefulSet、直接端点发现、分布式节点互访 |

### DNS 示例

下面使用 `busybox-subdomain` 和两个 Pod 说明 Headless Service 的 DNS 行为：

```yaml{8,20,21,36,37} [busybox-subdomain.yaml]
apiVersion: v1
kind: Service
metadata:
  name: busybox-subdomain
spec:
  selector:
    name: busybox
  clusterIP: None
  ports:
    - name: foo
      port: 1234
---
apiVersion: v1
kind: Pod
metadata:
  name: busybox1
  labels:
    name: busybox
spec:
  hostname: busybox-1
  subdomain: busybox-subdomain
  containers:
    - image: busybox:1.38
      command:
        - sleep
        - "3600"
      name: busybox
---
apiVersion: v1
kind: Pod
metadata:
  name: busybox2
  labels:
    name: busybox
spec:
  hostname: busybox-2
  subdomain: busybox-subdomain
  containers:
    - image: busybox:1.38
      command:
        - sleep
        - "3600"
      name: busybox
```

在同一 Namespace 中存在与 Pod `subdomain` 同名的 Headless Service 时，Pod 的 `hostname` 与 `subdomain` 会共同形成稳定 FQDN，例如：

```text
busybox-1.busybox-subdomain.my-namespace.svc.cluster-domain.example
```

Pod 需要 Ready 后才会获得对应 A 或 AAAA 记录，除非 Service 设置 `publishNotReadyAddresses: true`。

### StatefulSet 内部通信

Headless Service 常与 StatefulSet 配合使用，为每个 Pod 提供稳定 DNS 名称。StatefulSet 的 `spec.serviceName` 指向 Headless Service 后，Pod 可以获得与前文 [StatefulSet 固定 DNS 名称](../09-工作负载/2-StatefulSet.md#固定-dns-名称)相同的 `<pod-name>.<service-name>.<namespace>.svc.cluster.local` 格式。

示例：

```text
mysql-0.mysql.default.svc.cluster.local
mysql-1.mysql.default.svc.cluster.local
mysql-2.mysql.default.svc.cluster.local
```

这类稳定名称适合数据库、注册中心、消息队列、协调系统等需要节点身份的有状态应用。第 09 章 StatefulSet 已记录这类内部通信方式，此处只保留 Service 侧关系。

### 使用注意

Headless Service 把端点选择交给客户端或客户端库。调用方需要能够处理多个 DNS 结果、连接失败、端点变化和重试。

常见注意事项：

- 不适合作为所有无状态 Web 服务的默认选择
- 客户端 DNS 缓存行为会影响端点变化感知
- Pod 未 Ready 时通常不会出现在 DNS 结果中，除非 Service 配置 `publishNotReadyAddresses: true`
- 有状态集群需要结合 StatefulSet、稳定存储、探针和优雅退出共同设计

## Service 代理与排查

Service 访问链路依赖代理实现、EndpointSlice、DNS、Pod readiness 和底层网络共同工作。

### 代理模式

Service 的虚拟 IP 并不是某台机器真实绑定的业务 IP。默认实现中，每个节点上的 kube-proxy 会监听 Service 和 EndpointSlice 变化，并配置本机的数据面规则，把访问 Service IP、NodePort 或 LoadBalancer 后端入口的流量转发到实际端点。

不同环境中，Service 代理也可能由 CNI、eBPF 数据面或云厂商组件替代 kube-proxy。本文只记录 kube-proxy 常见模式。

| 平台      | kube-proxy 模式                |
|---------|------------------------------|
| Linux   | `iptables`、`ipvs`、`nftables` |
| Windows | `kernelspace`                |

### iptables 模式

`iptables` 模式通过 Linux netfilter/iptables 规则实现转发。kube-proxy 监听 Service 和 EndpointSlice 变化，为 Service 和后端端点生成规则。

基本流程如下：

| 步骤 | 行为                                       |
|----|------------------------------------------|
| 1  | kube-proxy 发现 Service 和 EndpointSlice 变化 |
| 2  | kube-proxy 生成或更新 iptables 规则             |
| 3  | 客户端访问 Service IP 和端口                     |
| 4  | 内核规则把流量 DNAT 到某个后端端点                     |
| 5  | 后端 Pod 处理请求并返回响应                         |

iptables 模式成熟、通用，适合大量集群。Kubernetes v1.28 之后 iptables 模式已经减少不必要的全量规则同步，但在超大规模 Service 与端点场景下仍需要观察 kube-proxy 指标和规则同步耗时。

### IPVS 模式

`ipvs` 模式使用 Linux IPVS 能力实现四层负载均衡，历史上常用于追求更高转发性能和更多调度算法的场景。

常见 IPVS 调度算法包括：

| 算法      | 含义             |
|---------|----------------|
| `rr`    | 轮询             |
| `wrr`   | 加权轮询           |
| `lc`    | 最少连接           |
| `wlc`   | 加权最少连接         |
| `lblc`  | 基于本地性的最少连接     |
| `lblcr` | 带复制的基于本地性的最少连接 |
| `sh`    | 源地址哈希          |
| `dh`    | 目的地址哈希         |
| `sed`   | 最短期望延迟         |
| `nq`    | 无需队列等待         |
| `mh`    | Maglev 哈希      |

kube-proxy 的 IPVS 模式自 v1.35 起被标记为 deprecated，配置为 `ipvs` 时 kube-proxy 会在启动时输出弃用警告。官方已在 KEP-5495 中给出分阶段移除计划：v1.37 引入 `KubeProxyIPVS` feature gate（默认 `true`）暂时保留该模式；计划 v1.40 起该 feature gate 默认关闭，未显式开启时 kube-proxy 将拒绝以 `ipvs` 模式启动；最早在 v1.43 移除相关实现。nftables 模式（v1.33 GA）是官方推荐的替代方向，iptables 模式仍为默认模式且未被弃用。

对于已有集群，是否继续使用 IPVS 应结合当前 Kubernetes 版本、网络插件支持情况和运维经验评估，尽早规划迁移到 nftables。对于新集群，不应再默认选择 IPVS。

查看当前代理模式：

```bash
kubectl get cm kube-proxy -n kube-system -o yaml
```

部分集群开启 kube-proxy metrics 后，也可以在节点上查看：

```bash
curl http://127.0.0.1:10249/proxyMode
```

如果集群仍使用 IPVS，可以在 kube-proxy 配置中看到类似字段。下面只展示代理模式与调度器字段，不是完整 `KubeProxyConfiguration`：

```yaml
mode: ipvs
ipvs:
  scheduler: rr
```

修改 kube-proxy 代理模式属于集群级网络变更，应先确认当前 Kubernetes 版本、内核模块、CNI 支持、回滚方式和维护窗口，不应在生产集群中直接临时修改。

### nftables 模式

`nftables` 模式使用 Linux nftables API 配置转发规则。它是 iptables 的后继方向，也是 IPVS 的官方推荐替代方案（自 v1.33 GA 起）。

使用 nftables 前需要关注：

- Linux 内核版本是否满足要求
- Kubernetes 版本是否支持该模式
- CNI 或网络插件是否兼容
- NodePort 监听地址、localhost NodePort、主机防火墙等行为差异
- 现有排障脚本是否依赖 iptables 或 ipvsadm 输出

代理模式的选择应综合功能兼容性、排障能力和团队经验，不应只看“性能更高”这一点。新集群建议优先评估 nftables 模式，已有集群在升级前应确认目标版本的兼容性。

### kernelspace 模式

Windows 节点上的 kube-proxy 使用 `kernelspace` 模式，在 Windows 内核网络栈中配置转发规则。混合 Linux 与 Windows 节点的集群需要分别确认数据面行为、网络插件支持和排障工具。

### 常用命令

Service 访问异常通常需要同时检查 Service、Pod、EndpointSlice、DNS 和节点代理规则。排查时可以按从抽象到后端的顺序展开。

查看 Service：

```bash
kubectl get svc
kubectl describe svc <service-name>
kubectl get svc <service-name> -o yaml
```

查看后端端点：

```bash
kubectl get eplices -l kubernetes.io/service-name=<service-name>
kubectl get ep <service-name>
```

EndpointSlice 是当前主线端点 API，`kubectl get ep` 主要用于兼容性观察或识别旧写法。

查看匹配 Pod：

```bash
kubectl get po -l <selector> -o wide
kubectl describe po <pod-name>
```

在具备 DNS 工具的调试 Pod 中检查解析和访问：

```bash
nslookup <service-name>.<namespace>.svc.cluster.local
curl http://<service-name>:<port>
```

> [!NOTE]
> 不同 `nslookup` 实现对 DNS 搜索列表的处理可能存在差异。检查 Service 的 DNS 记录时使用完整域名；验证同一 Namespace 内的短名称访问时，使用 `curl`、`wget` 或应用自身的网络客户端。

查看 kube-proxy：

```bash
kubectl get po -n kube-system -l k8s-app=kube-proxy -o wide
kubectl logs -n kube-system -l k8s-app=kube-proxy --tail=100
kubectl get cm kube-proxy -n kube-system -o yaml
```

### 常见问题

| 现象                                 | 可能原因                                                      | 检查方向                                                    |
|------------------------------------|-----------------------------------------------------------|---------------------------------------------------------|
| Service 没有后端端点                     | selector 与 Pod 标签不匹配                                      | `kubectl describe svc`、`kubectl get po --show-labels` |
| EndpointSlice 有端点但访问失败             | `targetPort` 错误、应用未监听、网络策略阻断                              | Pod 端口、容器日志、NetworkPolicy                               |
| DNS 无法解析 Service                   | CoreDNS 异常、Namespace 写错、DNS 策略异常                          | DNS 查询、CoreDNS Pod、Pod `/etc/resolv.conf`               |
| NodePort 外部不可访问                    | 防火墙或安全组未放行、访问了错误节点 IP                                     | 节点网络、端口范围、kube-proxy                                    |
| LoadBalancer 一直 pending            | 集群没有负载均衡实现                                                | 云控制器、MetalLB、Service 事件                                 |
| 会话保持不均衡                            | 多客户端共享源 IP 或上层代理改写源地址                                     | 源 IP、网关配置、Service 会话保持                                  |
| 无 selector Service 不能 port-forward | `kubectl port-forward` 需要按 selector 解析出后端 Pod，转发目标只能是 Pod | 改用可达网络路径，或为 Pod 后端补充 selector                           |

Service 的排查关键是不要只看 Service YAML。Service 是入口抽象，真正决定流量能否到达后端的，还包括 Pod readiness、EndpointSlice、DNS、kube-proxy、CNI 和外部网络边界。

### 配置建议

- Service selector 使用稳定标签，避免选择版本号、临时标记或容易变化的标签
- 多端口 Service 必须为每个端口设置清晰名称
- `targetPort` 可以优先引用容器端口名，降低端口号变更带来的影响
- 无状态服务默认使用 `ClusterIP`；对外 HTTP 入口优先放到 Ingress 或 Gateway API
- NodePort 适合实验、调试或对接外部负载均衡，不宜无规划暴露大量节点端口
- 外部依赖接入优先评估 ExternalName 与无 selector Service 的差异
- 有状态应用的内部发现优先结合 StatefulSet 与 Headless Service
- 双栈、流量策略、LoadBalancerClass 和 kube-proxy 模式都应结合当前集群实现确认
- 修改 kube-proxy 模式前先查阅当前版本和网络插件的官方文档

## 参考

本文内容参考以下 Kubernetes 英文文档、API Reference、kubectl 参考和示例文件：

- [Service](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Connecting Applications with Services](https://kubernetes.io/docs/tutorials/services/connect-applications-service/)
- [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [Virtual IPs and Service Proxies](https://kubernetes.io/docs/reference/networking/virtual-ips/)
- [IPv4/IPv6 dual-stack](https://kubernetes.io/docs/concepts/services-networking/dual-stack/)
- [EndpointSlices](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/)
- [Kubernetes v1.33: Continuing the transition from Endpoints to EndpointSlices](https://kubernetes.io/blog/2025/04/24/endpoints-deprecation/)
- [Service API reference](https://kubernetes.io/docs/reference/kubernetes-api/service-resources/service-v1/)
- [EndpointSlice API reference](https://kubernetes.io/docs/reference/kubernetes-api/service-resources/endpoint-slice-v1/)
- [Endpoints API reference](https://kubernetes.io/docs/reference/kubernetes-api/service-resources/endpoints-v1/)
- [kubectl expose](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_expose/)
- [run-my-nginx.yaml](https://raw.githubusercontent.com/kubernetes/website/main/content/en/examples/service/networking/run-my-nginx.yaml)
- [nginx-svc.yaml](https://raw.githubusercontent.com/kubernetes/website/main/content/en/examples/service/networking/nginx-svc.yaml)
- [nginx-secure-app.yaml](https://raw.githubusercontent.com/kubernetes/website/main/content/en/examples/service/networking/nginx-secure-app.yaml)
- [simple-service.yaml](https://raw.githubusercontent.com/kubernetes/website/main/content/en/examples/service/simple-service.yaml)
