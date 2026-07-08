# Ingress 控制器选型与 Gateway API 迁移

ingress-nginx 曾是使用最广泛的 Ingress Controller，它的退役使集群入口由哪个组件承接重新成为需要决策的问题。本文记录 ingress-nginx 退役时间线、仍在维护的 Ingress Controller 选型，以及向 Gateway API 迁移的路径与工具。

Ingress 资源的字段、路径匹配和 TLS 已在 [Ingress](./5-Ingress.md) 中记录，ingress-nginx 存量注解见[附录：ingress-nginx 存量注解参考](./appendix-ingress-nginx存量注解参考.md)。Gateway API 的完整资源模型和流量治理能力后续在网络入口内容中单独展开，本文只覆盖迁移决策需要的部分。

## 退役时间线

ingress-nginx 指 Kubernetes 社区维护的 `kubernetes/ingress-nginx` 项目，IngressClass 通常名为 `nginx`。关键节点如下：

| 时间         | 事件                                                                   |
|------------|----------------------------------------------------------------------|
| 2025-11-11 | Kubernetes 官方博客发布退役公告，宣布维护持续到 2026 年 3 月，之后项目退役                      |
| 2026-01-29 | Steering Committee 与 Security Response Committee 发布联合声明，要求所有用户立即开始迁移 |
| 2026-03-19 | 发布最终版本 controller v1.15.1 与 Helm chart 4.15.1                        |
| 2026-03 下旬 | GitHub 仓库归档为只读，项目正式退役                                                |

退役的实际含义：

- 不再发布新版本，不再修复缺陷，此后发现的任何安全漏洞都不会再被修复。
- 仓库转为只读归档，已发布的 Helm chart 和容器镜像仍可下载。
- 存量部署不会立即失效，但风险随时间累积。联合声明明确指出，退役后继续使用 ingress-nginx 会让集群和用户暴露在攻击风险中。
- 曾计划作为继任者的 InGate 项目未发展到可用程度，已一并退役。

确认集群中是否运行 ingress-nginx：

```bash
kubectl get pods --all-namespaces --selector app.kubernetes.io/name=ingress-nginx
```

> [!WARNING]
> Ingress NGINX 与 NGINX Ingress Controller 是两个不同项目：退役的是 Kubernetes 社区的 `kubernetes/ingress-nginx`；F5 维护的 NGINX Ingress Controller（`nginx/kubernetes-ingress`）不受影响，仍在持续维护。二者都使用 NGINX 作为数据面，但注解体系和配置方式互不兼容，不能直接混用文档。

## Ingress API 的状态

控制器退役不等于 Ingress API 被移除，二者层级不同：

- Ingress API 保持 GA 状态，遵循正式 API 的稳定性保证，官方没有移除计划。
- Ingress API 已冻结，不再开发新能力，后续不会再有任何变更。
- Kubernetes 官方推荐使用 Gateway API 取代 Ingress。

存量 Ingress 资源不需要立即改写，真正必须替换的是数据面控制器。新入口设计应优先评估 Gateway API。

## Ingress Controller 选型

如果暂时继续使用 Ingress API，需要换用仍在维护的控制器。Kubernetes 官方 Ingress Controllers 列表已移除 ingress-nginx，当前由 Kubernetes 项目自身维护的只剩 AWS 与 GCE 两个云平台控制器，其余均为第三方项目。常见选项：

| 控制器                          | 数据面             | 记录要点                                      |
|------------------------------|-----------------|-------------------------------------------|
| Traefik                      | Traefik         | 同时支持 Ingress 与 Gateway API，动态配置能力强        |
| HAProxy Ingress              | HAProxy         | 同时支持 Ingress 与 Gateway API                |
| NGINX Ingress Controller（F5） | NGINX           | 数据面同为 NGINX，但注解不兼容 ingress-nginx，迁移仍需逐条改写 |
| Cilium                       | eBPF + Envoy    | CNI 与入口一体，减少独立入口组件                        |
| Istio Ingress Gateway        | Envoy           | 已使用 Istio 服务网格的集群顺路承接入口                   |
| Kong、APISIX                  | OpenResty/NGINX | 偏 API 网关场景，提供认证、限流等插件体系                   |
| 云厂商控制器                       | 云负载均衡           | AWS ALB、GCE 等托管环境优先评估                     |

没有任何控制器能直接平替 ingress-nginx。选型时重点核对：

- 注解兼容性：`nginx.ingress.kubernetes.io/*` 注解不可平移，rewrite、正则路径、金丝雀、限流等能力需要在目标控制器中重新表达。
- 是否同时实现 Gateway API：选择双栈控制器可以把控制器替换和 API 迁移合并为一次演进。
- 数据面运维经验：团队对 NGINX、HAProxy、Envoy 的排障熟悉度直接影响故障恢复速度。
- 行为差异验证：路径匹配、默认后端、转发头、超时和重定向的默认行为各控制器不同，切换前需要逐项回归。

## Gateway API 资源模型

Gateway API 是 Kubernetes 官方维护的下一代入口与流量路由 API，用于替代 Ingress。它以 CRD 形式发布，不随集群内置，需要先安装 CRD 再部署某个实现。

Gateway API 最核心的四个稳定资源如下，均为 `gateway.networking.k8s.io/v1`：

| 资源           | 作用域         | 职责                                       |
|--------------|-------------|------------------------------------------|
| GatewayClass | 集群级         | 声明一类网关由哪个控制器实现，类似 IngressClass           |
| Gateway      | Namespace 级 | 声明一个具体网关实例的监听端口、协议和 TLS 配置               |
| HTTPRoute    | Namespace 级 | 声明 HTTP 路由规则，通过 `parentRefs` 挂接到 Gateway |
| GRPCRoute    | Namespace 级 | 声明 gRPC 路由规则                             |

与 Ingress 相比的主要变化：

- 角色分离：GatewayClass 由实现方提供，Gateway 由平台团队管理，Route 由业务团队管理，路由可以跨 Namespace 挂接到共享网关。
- 表达能力进入 API 本身：Header 匹配、流量拆分、重定向、重写等能力是标准字段，不再依赖控制器注解。
- 协议范围更广：Standard channel 在 HTTP、gRPC 之外还包含 TLSRoute、TCPRoute、UDPRoute；TCPRoute 与 UDPRoute 自 v1.6 起为 GA，四层路由不再是实验特性。

Gateway API 采用 Standard 与 Experimental 两个发布渠道。Standard channel 安装稳定资源；Experimental channel 额外包含实验资源和实验字段，字段可能变更或移除，生产集群应默认使用 Standard channel。

## 部署 Gateway API

安装 Standard channel CRD（当前最新版本为 v1.6.0，2026-06 发布）：

```bash
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.0/standard-install.yaml
```

CRD 只定义 API，还需要部署一个实现作为控制器。实现的安装方式以各项目官方文档为准，完整列表和一致性状态见 [Gateway API implementations](https://gateway-api.sigs.k8s.io/docs/implementations/list/)。截至 2026 年 7 月，通过一致性测试的实现包括 Cilium、Istio、Traefik Proxy、NGINX Gateway Fabric、Envoy Gateway、kgateway、Gloo Gateway、HAProxy Ingress、GKE 等；Kong 的 Gateway API 投入已转向 Kong Operator，后者当前为部分一致状态。

实现部署完成后，确认可用的 GatewayClass：

```bash
kubectl get gatewayclass
```

下面示例将 [Ingress](./5-Ingress.md) 中 `study-ingress` 的入口改写为 Gateway API 资源，复用其中的 Namespace、Deployment 和 Service，`gatewayClassName` 需要替换为集群中实际存在的 GatewayClass 名称：

```yaml [gateway-demo.yaml]
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: web-gateway
  namespace: study-ingress
spec:
  gatewayClassName: <gateway-class-name>
  listeners:
    - name: http
      protocol: HTTP
      port: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: nginx
  namespace: study-ingress
spec:
  parentRefs:
    - name: web-gateway
  hostnames:
    - nginx.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: nginx
          port: 80
```

应用后查看 Gateway 和 HTTPRoute 状态：

```bash
kubectl apply -f gateway-demo.yaml
kubectl get gateway -n study-ingress
kubectl get httproute -n study-ingress
kubectl describe httproute nginx -n study-ingress
```

Gateway 的访问地址由实现写入 `status.addresses`，HTTPRoute 是否成功挂接可以在 `status.parents` 的 `Accepted` 条件中确认。与 Ingress 一样，地址类型取决于实现和暴露方式。

## 使用 ingress2gateway 转换

[ingress2gateway](https://github.com/kubernetes-sigs/ingress2gateway) 是 SIG Network 维护的迁移工具，读取集群或文件中的 Ingress 及控制器特有注解，输出等价的 Gateway API 资源。v1.0.0 于 2026 年 3 月发布，对 ingress-nginx 的注解支持扩展到 30 余个，覆盖 CORS、后端 TLS、正则匹配和路径重写等常用注解。

从当前 kubeconfig 上下文读取 Ingress 并输出转换结果：

```bash
ingress2gateway print --providers=ingress-nginx --all-namespaces > gateway-migration.yaml
```

工具的定位是迁移助手而不是一键替换：

- 无法翻译的注解会输出警告，例如 `configuration-snippet` 这类直接注入 NGINX 配置的注解没有 Gateway API 等价物，需要人工改写。
- 转换结果必须逐条审查并在测试环境验证，不应直接应用到生产集群。
- 路由行为存在语义差异：ingress-nginx 的正则路径是前缀式且大小写不敏感，Envoy 系实现是完整且大小写敏感匹配；默认后端、转发头和重定向行为也可能不同。

官方针对 ingress-nginx 用户提供了专门的迁移指南和常见行为差异说明，见文末参考。

## 迁移记录要点

- 先用标签自查集群中的 ingress-nginx 部署，盘点入口数量、注解使用情况和 TLS 证书分布。
- 明确目标形态：继续 Ingress API 换控制器，或直接迁移 Gateway API；新入口不再基于 ingress-nginx 设计。
- 存量制品仍可拉取不代表安全，退役后未修复的 CVE 会持续累积，迁移窗口应按安全风险而不是功能需求排期。
- 转换结果在独立 Namespace 或测试集群中并行验证，通过流量比对确认行为一致后再切换 DNS 或负载均衡指向。
- 切换后保留旧入口一段时间作为回退路径，确认监控、日志和告警已经覆盖新控制器。

## 参考

- [Ingress NGINX Retirement: What You Need to Know](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/)
- [Ingress NGINX: Statement from the Kubernetes Steering and Security Response Committees](https://kubernetes.io/blog/2026/01/29/ingress-nginx-statement/)
- [Gateway API](https://kubernetes.io/docs/concepts/services-networking/gateway/)
- [Ingress Controllers](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/)
- [Gateway API Getting Started](https://gateway-api.sigs.k8s.io/guides/getting-started/introduction/)
- [Gateway API implementations](https://gateway-api.sigs.k8s.io/docs/implementations/list/)
- [Migrating from Ingress NGINX](https://gateway-api.sigs.k8s.io/guides/getting-started/migrating-from-ingress-nginx/)
- [Before You Migrate: Five Surprising Ingress-NGINX Behaviors](https://kubernetes.io/blog/2026/02/27/ingress-nginx-before-you-migrate/)
- [Announcing Ingress2Gateway 1.0](https://kubernetes.io/blog/2026/03/20/ingress2gateway-1-0-release/)
- [ingress2gateway](https://github.com/kubernetes-sigs/ingress2gateway)
