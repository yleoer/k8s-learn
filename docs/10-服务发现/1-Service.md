# Service

Service 是 Kubernetes 为后端 Pod 或其他网络端点提供稳定访问入口的核心资源。Service 通过固定名称、固定虚拟 IP 或固定端口屏蔽后端端点变化，调用方不需要直接维护 Pod IP 或外部地址列表。

本文记录 Service 资源定义、Service 类型、流量策略、双栈地址族、多端口和会话保持。EndpointSlice、DNS、Headless Service、代理模式和排查记录拆分到后续文档。

## Service 定义与访问

Service 的基础配置集中在 `metadata.name`、`spec.selector`、`spec.ports` 和 `spec.type`。其中 `metadata.name` 会参与集群内 DNS 名称生成，`selector` 决定后端 Pod 范围，`ports` 决定 Service 暴露端口与后端端口的映射关系。

### 创建与查看

可以先创建 `my-nginx` Deployment，再通过 `kubectl expose` 生成 Service：

```bash
kubectl apply -f ./run-my-nginx.yaml
kubectl expose deployment/my-nginx
kubectl get svc my-nginx
kubectl describe svc my-nginx
kubectl get endpointslices -l kubernetes.io/service-name=my-nginx
```

`kubectl expose` 会查找指定 Deployment、Service、ReplicaSet、ReplicationController 或 Pod，并使用该资源的 selector 为新 Service 生成 selector。长期维护时仍建议保存 Service YAML，并通过声明式方式管理。

### 基础字段

| 字段 | 是否必选 | 说明 |
| --- | --- | --- |
| `apiVersion` | 是 | Service 使用 `v1` |
| `kind` | 是 | 资源类型，固定为 `Service` |
| `metadata.name` | 是 | Service 名称，同一 Namespace 内唯一，也会成为 DNS 名称的一部分 |
| `spec.selector` | 否 | 用于选择后端 Pod；ExternalName 不使用该字段；无 selector Service 不会自动生成 EndpointSlice |
| `spec.ports` | 视类型而定 | Service 暴露端口列表；ExternalName 可以不定义端口 |
| `spec.ports[].name` | 多端口时必选 | 端口名称，同一个 Service 内需要唯一 |
| `spec.ports[].port` | 是 | Service 自身暴露的端口 |
| `spec.ports[].targetPort` | 否 | 后端端口，未配置时默认等于 `port` |
| `spec.ports[].protocol` | 否 | 协议，默认 `TCP`，也可使用 `UDP`、`SCTP` |
| `spec.ports[].appProtocol` | 否 | 应用协议提示，会镜像到对应 EndpointSlice |
| `spec.type` | 否 | Service 类型，默认 `ClusterIP` |
| `spec.sessionAffinity` | 否 | 会话保持配置，默认 `None` |

查看字段说明：

```bash
kubectl explain service.spec
kubectl explain service.spec.ports
```

### 端口映射

Service 端口与后端 Pod 端口可以不同。端口命名示例如下：

```yaml
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
      image: nginx:stable
      ports:
        - containerPort: 80
          name: http-web-svc
```

这里 `targetPort: http-web-svc` 引用了 Pod 中定义的容器端口名。端口名可以降低 Service 与容器端口号之间的耦合，但需要保证端口名在 Pod 模板中真实存在。

## Service 类型

Service 通过 `spec.type` 决定暴露方式。常见类型包括 `ClusterIP`、`NodePort`、`LoadBalancer` 和 `ExternalName`。

| 类型 | 访问范围 | 典型用途 |
| --- | --- | --- |
| `ClusterIP` | 集群内部 | 服务间访问，默认类型 |
| `NodePort` | 节点 IP 加固定端口 | 简单暴露集群内服务，常用于实验或对接外部负载均衡 |
| `LoadBalancer` | 云厂商或负载均衡实现提供的外部地址 | 云环境对外发布四层服务 |
| `ExternalName` | DNS CNAME 别名 | 在集群内用 Service 名称引用外部域名 |

`NodePort` 和 `LoadBalancer` 都建立在 `ClusterIP` 能力之上。`ExternalName` 不会创建普通代理规则，也不转发到 Pod。

### ClusterIP

`ClusterIP` 是默认类型。Kubernetes 会为 Service 分配一个集群内部虚拟 IP，客户端通过 Service 名称或 ClusterIP 访问后端 Pod。

下面的 `my-nginx` Service 未显式声明 `spec.type`，因此会创建为 `ClusterIP`：

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-nginx
  labels:
    run: my-nginx
spec:
  ports:
    - port: 80
      protocol: TCP
  selector:
    run: my-nginx
```

ClusterIP 通常只在集群内可达。集群外访问业务服务时，应根据环境选择 Ingress、Gateway API、LoadBalancer 或 NodePort。

### NodePort

`NodePort` 会在每个运行 kube-proxy 的节点上打开一个端口，并把该端口的流量转发到 Service 后端。访问形式通常是：

```text
<node-ip>:<node-port>
```

以下 Service 片段用于说明 NodePort 与多端口字段关系；完整应用清单还需要包含对应后端工作负载：

```yaml
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
kubectl describe service my-nginx
```

如果 `EXTERNAL-IP` 长时间处于 `pending`，通常说明当前集群没有可用的 LoadBalancer 实现。裸金属环境可以结合 MetalLB、kube-vip 或云厂商提供的控制器来实现。

`LoadBalancer` 相关字段需要特别区分：

| 字段 | 说明 |
| --- | --- |
| `spec.loadBalancerClass` | 指定非默认负载均衡实现，只能用于 `LoadBalancer` 类型，设置后不可变 |
| `spec.allocateLoadBalancerNodePorts` | 默认为 `true`；支持直连 Pod 的负载均衡实现可以设置为 `false` |
| `spec.loadBalancerIP` | v1.24 起 deprecated，语义在不同实现中不一致，也无法支持双栈；应改用实现特定的 annotation |

`LoadBalancer` 适合暴露少量四层服务。HTTP、HTTPS 多域名和路径路由更常放在 Ingress 或 Gateway API 中统一管理。

### ExternalName

`ExternalName` 通过 DNS CNAME 把 Service 名称映射到外部域名。它不创建 ClusterIP，也不通过 kube-proxy 转发流量。

下面示例把 `prod` Namespace 中的 `my-service` 映射到 `my.database.example.com`：

```yaml
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

| 字段 | 可选值 | 行为 |
| --- | --- | --- |
| `spec.internalTrafficPolicy` | `Cluster`、`Local` | 控制集群内部来源流量；`Cluster` 使用所有就绪端点，`Local` 只使用节点本地就绪端点 |
| `spec.externalTrafficPolicy` | `Cluster`、`Local` | 控制外部来源流量；`Cluster` 使用所有就绪端点，`Local` 只使用节点本地就绪端点 |

`Cluster` 是默认行为。`Local` 提供更强的本地性约束：如果当前节点没有本地就绪端点，对应流量不会被转发到其他节点。`externalTrafficPolicy: Local` 常用于保留客户端源 IP，但需要配合负载均衡健康检查、Pod 分布和滚动更新策略评估可用性。

### 流量分布

`spec.trafficDistribution` 用于表达端点选择偏好。它不同于 `internalTrafficPolicy` 和 `externalTrafficPolicy` 的强约束，更适合表达拓扑接近性：

| 值 | 含义 |
| --- | --- |
| `PreferSameZone` | 优先选择与客户端处于同一 zone 的端点 |
| `PreferSameNode` | 优先选择与客户端处于同一节点的端点 |
| `PreferClose` | `PreferSameZone` 的旧别名，v1.36 中已标记为 deprecated；建议改用 `PreferSameZone` |

未设置 `trafficDistribution` 时，默认策略是在集群内所有端点之间分布流量。若对应流量类型的 `internalTrafficPolicy` 或 `externalTrafficPolicy` 设置为 `Local`，该强约束优先于 `trafficDistribution`。

EndpointSlice 可以携带 `hints`、`zone`、`nodeName` 等信息，供支持拓扑感知的实现使用。旧的 `service.kubernetes.io/topology-mode: Auto` 注解已在 `trafficDistribution` 达到 GA 后废弃，不应在新配置中使用。

## 双栈与地址族

Kubernetes 支持 IPv4 单栈、IPv6 单栈以及 IPv4/IPv6 双栈 Service。双栈是否可用取决于集群网络插件、控制面参数、节点网络和负载均衡实现。

Service 地址族相关字段如下：

| 字段 | 说明 |
| --- | --- |
| `spec.ipFamilyPolicy` | 控制单栈或双栈分配策略 |
| `spec.ipFamilies` | 指定地址族以及双栈时的顺序 |
| `spec.clusterIPs` | 记录实际分配的一个或两个 ClusterIP |
| `spec.clusterIP` | 旧字段，取自 `clusterIPs` 的第一个值 |

`ipFamilyPolicy` 的常见取值：

| 值 | 行为 |
| --- | --- |
| `SingleStack` | 分配单个地址族的 ClusterIP |
| `PreferDualStack` | 双栈可用时分配 IPv4 和 IPv6；不可用时回退到单栈 |
| `RequireDualStack` | 要求分配 IPv4 和 IPv6；双栈不可用时创建失败 |

显式请求双栈可以写为：

```yaml
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

```yaml
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


## 参考

本文内容参考以下 Kubernetes 英文文档、API Reference、kubectl 参考和示例文件：

- [Service](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Connecting Applications with Services](https://kubernetes.io/docs/tutorials/services/connect-applications-service/)
- [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [Virtual IPs and Service Proxies](https://kubernetes.io/docs/reference/networking/virtual-ips/)
- [IPv4/IPv6 dual-stack](https://kubernetes.io/docs/concepts/services-networking/dual-stack/)
- [EndpointSlices](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/)
- [Service API reference](https://kubernetes.io/docs/reference/kubernetes-api/service-resources/service-v1/)
- [EndpointSlice API reference](https://kubernetes.io/docs/reference/kubernetes-api/service-resources/endpoint-slice-v1/)
- [Endpoints API reference](https://kubernetes.io/docs/reference/kubernetes-api/service-resources/endpoints-v1/)
- [kubectl expose](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_expose/)
- [run-my-nginx.yaml](https://raw.githubusercontent.com/kubernetes/website/main/content/en/examples/service/networking/run-my-nginx.yaml)
- [nginx-svc.yaml](https://raw.githubusercontent.com/kubernetes/website/main/content/en/examples/service/networking/nginx-svc.yaml)
- [nginx-secure-app.yaml](https://raw.githubusercontent.com/kubernetes/website/main/content/en/examples/service/networking/nginx-secure-app.yaml)
- [simple-service.yaml](https://raw.githubusercontent.com/kubernetes/website/main/content/en/examples/service/simple-service.yaml)
