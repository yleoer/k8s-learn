# EndpointSlice 与 DNS

Service 的后端端点由 EndpointSlice 表示，集群 DNS 则为 Service 提供稳定名称。本文记录 EndpointSlice 的维护方式、无 selector Service、Endpoints 兼容关系、Service DNS 记录和环境变量发现。

## EndpointSlice

Service 本身记录的是访问抽象，后端真实地址由 EndpointSlice 表示。EndpointSlice 会保存一组后端端点的 IP、端口、协议、就绪状态、所在节点和拓扑信息，供 kube-proxy、DNS 和其他控制器消费。

早期 Kubernetes 使用 Endpoints 资源记录后端地址。当前主线中，EndpointSlice 是更推荐关注的后端端点 API；Endpoints API 已在 v1.33 被标记为 deprecated。

### 自动维护过程

对于带 selector 的 Service，控制器会根据匹配 Pod 自动维护 EndpointSlice：

| 步骤 | 行为 |
| --- | --- |
| 1 | 创建 Service，配置 `spec.selector` |
| 2 | 控制器查找标签匹配的 Pod |
| 3 | 控制器为 Service 创建或更新 EndpointSlice |
| 4 | kube-proxy 监听 Service 和 EndpointSlice 变化 |
| 5 | 节点上的代理规则更新，流量可以转发到就绪端点 |

查看 Service 与 EndpointSlice：

```bash
kubectl get svc my-nginx
kubectl get endpointslices -l kubernetes.io/service-name=my-nginx
kubectl describe endpointslices -l kubernetes.io/service-name=my-nginx
```

排查旧组件或兼容性问题时，也可以查看 Endpoints：

```bash
kubectl get endpoints my-nginx
```

如果 Service 可以解析但访问失败，应同时查看 Pod readiness 状态和 EndpointSlice 内容：

```bash
kubectl get pods -l run=my-nginx -o wide
kubectl get endpointslices -l kubernetes.io/service-name=my-nginx -o yaml
kubectl describe svc my-nginx
```

EndpointSlice 中每个端点有三种状态条件：`conditions.serving` 表示端点正在提供服务（对应 Pod 的 Ready 状态）；`conditions.terminating` 表示端点正在终止中（Pod 已收到删除时间戳）；`conditions.ready` 是 `serving && !terminating` 的快捷表达，常用于兼容性查询。对于 Pod 后端，控制器根据 Pod Ready 状态、终止状态以及 Service 的 `publishNotReadyAddresses` 配置计算这些条件。Pod 未 Ready、selector 不匹配、端口名写错，都可能导致 Service 没有可用后端。

### 无 selector Service

Service 可以不配置 selector，此时 Kubernetes 不会自动创建后端端点。需要手动创建 EndpointSlice，把 Service 名称与端点关联起来。

这种方式常用于在集群内用固定 Service 名称访问外部系统，例如迁移期间仍运行在集群外的数据库、缓存或旧服务。

下面清单展示无 selector Service 与手动 EndpointSlice 的对应关系，并使用 `endpointslice.kubernetes.io/managed-by` 标识维护方：

```yaml
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

新配置应优先使用 EndpointSlice。`kubectl get endpoints` 主要用于兼容性观察、识别旧写法或排查仍依赖 Endpoints 的旧组件。

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

## 多端口与会话保持

一个 Service 可以同时暴露多个端口，适合一个后端 Pod 提供多个协议或管理端口的场景。多端口 Service 中，每个端口都必须设置唯一名称。

### 多端口 Service

多端口 Service 示例：

```yaml
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

| 字段 | 说明 |
| --- | --- |
| `sessionAffinity: None` | 默认值，不启用会话保持 |
| `sessionAffinity: ClientIP` | 按客户端 IP 做会话保持 |
| `sessionAffinityConfig.clientIP.timeoutSeconds` | 粘性会话保持时间，默认 10800 秒 |

会话保持适合短期兼容依赖本地会话的应用。长期看，更推荐把会话状态放到共享存储、缓存或数据库中，让任意副本都可以处理请求。

需要注意，客户端 IP 可能经过 NAT、代理或网关改写。大量客户端共享同一个源 IP 时，`ClientIP` 可能导致流量集中到少数 Pod。


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
