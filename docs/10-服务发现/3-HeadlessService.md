# Headless Service

Headless Service 不分配 ClusterIP，DNS 会直接返回后端端点地址。本文记录 Headless Service 的 DNS 行为、与 StatefulSet 的关系以及使用注意。

## 工作方式

Headless Service 是不分配 ClusterIP 的 Service，配置方式是 `clusterIP: None`。它不提供普通 Service 的虚拟 IP，DNS 会直接返回后端端点地址。

普通 Service 与 Headless Service 的核心区别如下：

| 对比项 | 普通 Service | Headless Service |
| --- | --- | --- |
| ClusterIP | 分配虚拟 IP | `None` |
| DNS 结果 | Service ClusterIP | 后端端点 IP 集合 |
| 代理转发 | 通常经过 kube-proxy 代理规则 | 客户端直接连接解析到的端点 |
| 常见用途 | 无状态服务统一入口 | StatefulSet、直接端点发现、分布式节点互访 |

### DNS 示例

下面使用 `busybox-subdomain` 和两个 Pod 说明 Headless Service 的 DNS 行为：

```yaml
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
    - image: busybox:1.28
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
    - image: busybox:1.28
      command:
        - sleep
        - "3600"
      name: busybox
```

在同一 Namespace 中存在同名 Headless Service 时，Pod 的 `hostname` 与 `subdomain` 会共同形成稳定 FQDN，例如：

```text
busybox-1.busybox-subdomain.my-namespace.svc.cluster-domain.example
```

Pod 需要 Ready 后才会获得对应 A 或 AAAA 记录，除非 Service 设置 `publishNotReadyAddresses: true`。

### StatefulSet 内部通信

Headless Service 常与 StatefulSet 配合使用，为每个 Pod 提供稳定 DNS 名称。StatefulSet 的 `spec.serviceName` 指向 Headless Service 后，Pod 可以获得如下形式的稳定访问名：

```text
<pod-name>.<service-name>.<namespace>.svc.cluster.local
```

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
