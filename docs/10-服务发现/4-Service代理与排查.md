# Service 代理与排查

Service 访问链路依赖代理实现、EndpointSlice、DNS、Pod readiness 和底层网络共同工作。本文记录 kube-proxy 常见代理模式、访问异常排查方法和配置建议。

## 代理模式

Service 的虚拟 IP 并不是某台机器真实绑定的业务 IP。默认实现中，每个节点上的 kube-proxy 会监听 Service 和 EndpointSlice 变化，并配置本机的数据面规则，把访问 Service IP、NodePort 或 LoadBalancer 后端入口的流量转发到实际端点。

不同环境中，Service 代理也可能由 CNI、eBPF 数据面或云厂商组件替代 kube-proxy。本文只记录 kube-proxy 常见模式。

| 平台 | kube-proxy 模式 |
| --- | --- |
| Linux | `iptables`、`ipvs`、`nftables` |
| Windows | `kernelspace` |

### iptables 模式

`iptables` 模式通过 Linux netfilter/iptables 规则实现转发。kube-proxy 监听 Service 和 EndpointSlice 变化，为 Service 和后端端点生成规则。

基本流程如下：

| 步骤 | 行为 |
| --- | --- |
| 1 | kube-proxy 发现 Service 和 EndpointSlice 变化 |
| 2 | kube-proxy 生成或更新 iptables 规则 |
| 3 | 客户端访问 Service IP 和端口 |
| 4 | 内核规则把流量 DNAT 到某个后端端点 |
| 5 | 后端 Pod 处理请求并返回响应 |

iptables 模式成熟、通用，适合大量集群。Kubernetes v1.28 之后 iptables 模式已经减少不必要的全量规则同步，但在超大规模 Service 与端点场景下仍需要观察 kube-proxy 指标和规则同步耗时。

### IPVS 模式

`ipvs` 模式使用 Linux IPVS 能力实现四层负载均衡，历史上常用于追求更高转发性能和更多调度算法的场景。

常见 IPVS 调度算法包括：

| 算法 | 含义 |
| --- | --- |
| `rr` | 轮询 |
| `wrr` | 加权轮询 |
| `lc` | 最少连接 |
| `wlc` | 加权最少连接 |
| `lblc` | 基于本地性的最少连接 |
| `lblcr` | 带复制的基于本地性的最少连接 |
| `sh` | 源地址哈希 |
| `dh` | 目的地址哈希 |
| `sed` | 最短期望延迟 |
| `nq` | 无需队列等待 |
| `mh` | Maglev 哈希 |

kube-proxy 的 IPVS 模式自 v1.35（2025 年 12 月发布）起被标记为 deprecated。计划在 v1.40 默认禁用（通过 `KubeProxyIPVS` feature gate），并在 v1.43 从代码库中完全移除。nftables 模式（v1.33 GA）是官方推荐的替代方向，iptables 模式仍为默认模式且未被弃用。

对于已有集群，是否继续使用 IPVS 应结合当前 Kubernetes 版本、网络插件支持情况和运维经验评估，尽早规划迁移到 nftables。对于新集群，不应再默认选择 IPVS。

查看当前代理模式：

```bash
kubectl get configmap kube-proxy -n kube-system -o yaml
```

部分集群开启 kube-proxy metrics 后，也可以在节点上查看：

```bash
curl http://127.0.0.1:10249/proxyMode
```

如果集群仍使用 IPVS，可以在 kube-proxy 配置中看到类似字段：

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

## 排查记录

Service 访问异常通常需要同时检查 Service、Pod、EndpointSlice、DNS 和节点代理规则。排查时可以按从抽象到后端的顺序展开。

### 常用命令

查看 Service：

```bash
kubectl get svc
kubectl describe svc <service-name>
kubectl get svc <service-name> -o yaml
```

查看后端端点：

```bash
kubectl get endpointslices -l kubernetes.io/service-name=<service-name>
kubectl get endpoints <service-name>
```

EndpointSlice 是当前主线端点 API，`kubectl get endpoints` 主要用于兼容性观察或识别旧写法。

查看匹配 Pod：

```bash
kubectl get pods -l <selector> -o wide
kubectl describe pod <pod-name>
```

在具备 DNS 工具的调试 Pod 中检查解析和访问：

```bash
nslookup <service-name>
nslookup <service-name>.<namespace>.svc.cluster.local
curl http://<service-name>:<port>
```

查看 kube-proxy：

```bash
kubectl get pods -n kube-system -l k8s-app=kube-proxy -o wide
kubectl logs -n kube-system -l k8s-app=kube-proxy --tail=100
kubectl get configmap kube-proxy -n kube-system -o yaml
```

### 常见问题

| 现象 | 可能原因 | 检查方向 |
| --- | --- | --- |
| Service 没有后端端点 | selector 与 Pod 标签不匹配 | `kubectl describe svc`、`kubectl get pods --show-labels` |
| EndpointSlice 有端点但访问失败 | `targetPort` 错误、应用未监听、网络策略阻断 | Pod 端口、容器日志、NetworkPolicy |
| DNS 无法解析 Service | CoreDNS 异常、Namespace 写错、DNS 策略异常 | DNS 查询、CoreDNS Pod、Pod `/etc/resolv.conf` |
| NodePort 外部不可访问 | 防火墙或安全组未放行、访问了错误节点 IP | 节点网络、端口范围、kube-proxy |
| LoadBalancer 一直 pending | 集群没有负载均衡实现 | 云控制器、MetalLB、Service 事件 |
| 会话保持不均衡 | 多客户端共享源 IP 或上层代理改写源地址 | 源 IP、网关配置、Service 会话保持 |
| 无 selector Service 不能 port-forward | API server 不允许代理到非 Pod 端点 | 改用可达网络路径或为 Pod 后端配置 selector |

Service 的排查关键是不要只看 Service YAML。Service 是入口抽象，真正决定流量能否到达后端的，还包括 Pod readiness、EndpointSlice、DNS、kube-proxy、CNI 和外部网络边界。

## 配置建议

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
- [Service API reference](https://kubernetes.io/docs/reference/kubernetes-api/service-resources/service-v1/)
- [EndpointSlice API reference](https://kubernetes.io/docs/reference/kubernetes-api/service-resources/endpoint-slice-v1/)
- [Endpoints API reference](https://kubernetes.io/docs/reference/kubernetes-api/service-resources/endpoints-v1/)
- [kubectl expose](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_expose/)
- [run-my-nginx.yaml](https://raw.githubusercontent.com/kubernetes/website/main/content/en/examples/service/networking/run-my-nginx.yaml)
- [nginx-svc.yaml](https://raw.githubusercontent.com/kubernetes/website/main/content/en/examples/service/networking/nginx-svc.yaml)
- [nginx-secure-app.yaml](https://raw.githubusercontent.com/kubernetes/website/main/content/en/examples/service/networking/nginx-secure-app.yaml)
- [simple-service.yaml](https://raw.githubusercontent.com/kubernetes/website/main/content/en/examples/service/simple-service.yaml)
