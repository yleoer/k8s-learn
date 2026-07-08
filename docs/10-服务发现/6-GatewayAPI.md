# Gateway API

Gateway API 是 Kubernetes SIG Network 维护的下一代服务网络 API。它以 CRD 形式安装，不随 Kubernetes 核心组件内置；真正的数据面仍需要 Traefik、Cilium、Istio、Envoy Gateway、HAProxy Ingress 等实现来监听资源并转发流量。

本文记录 Gateway API 与 Ingress 的关系、核心资源模型、最小 HTTP 路由示例和从 Ingress 迁移时需要关注的边界。Traefik 作为实现的安装和控制器特性见 [Traefik](./7-Traefik.md)，ingress-nginx 存量迁移背景见[附录：ingress-nginx](./appendix-ingress-nginx.md)。

## 资源边界

Ingress 把入口监听、域名、路径、TLS 和后端路由压缩在一个资源中，扩展能力通常依赖控制器私有注解。Gateway API 把入口职责拆成多个资源，便于平台团队和业务团队分开管理。

常见对象关系如下：

```text
GatewayClass -> Gateway <- HTTPRoute -> Service -> Pod
```

核心资源说明：

| 资源           | 作用域         | 职责                                       |
|--------------|-------------|------------------------------------------|
| GatewayClass | 集群级         | 声明一类网关由哪个控制器实现，类似 IngressClass           |
| Gateway      | Namespace 级 | 声明具体网关实例的监听端口、协议、Host 限制和 TLS 配置        |
| HTTPRoute    | Namespace 级 | 声明 HTTP 路由规则，通过 `parentRefs` 挂接到 Gateway |
| GRPCRoute    | Namespace 级 | 声明 gRPC 路由规则                             |
| TLSRoute     | Namespace 级 | 声明 TLS 路由规则                              |
| TCPRoute     | Namespace 级 | 声明 TCP 路由规则                              |
| UDPRoute     | Namespace 级 | 声明 UDP 路由规则                              |
| ReferenceGrant | Namespace 级 | 允许跨 Namespace 引用后端或 Secret 等资源             |

Gateway API 采用 Standard 与 Experimental 两个发布渠道。生产环境应优先安装 Standard channel；Experimental channel 包含实验资源和实验字段，后续可能变更或移除。

## 与 Ingress 的区别

Gateway API 不是 Ingress Controller，也不是代理进程。它是一组 Kubernetes API，需要具体实现来生效。

主要区别如下：

| 维度     | Ingress                         | Gateway API                              |
|--------|---------------------------------|------------------------------------------|
| API 形态 | Kubernetes 内置稳定 API             | CRD，需要单独安装                              |
| 职责拆分   | 一个 Ingress 同时表达入口和路由          | Gateway 管入口，Route 管路由                   |
| 扩展方式   | 多依赖控制器私有注解                    | 常用能力进入结构化字段，扩展通过 Policy、ExtensionRef 等方式 |
| 多团队协作  | 较弱，常由业务直接持有入口配置               | 更适合平台团队管理 Gateway、业务团队管理 Route          |
| 协议范围   | HTTP、HTTPS                      | HTTP、gRPC、TLS、TCP、UDP 等，取决于资源和实现支持      |

Gateway API 不包含 Ingress kind。已有 Ingress 资源迁移到 Gateway API 时，需要转换成 Gateway、HTTPRoute 等资源，而不是直接由 Gateway API “接管”原 Ingress。

## 安装 CRD

Gateway API 的 CRD 由 `kubernetes-sigs/gateway-api` 发布。下面以 v1.6.0 的 Standard channel 为例：

```bash
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.0/standard-install.yaml
```

CRD 只定义 API，不会创建数据面。安装 CRD 后还需要部署一个 Gateway API 实现，例如 Traefik、Cilium、Istio、Envoy Gateway、HAProxy Ingress 或云厂商实现。实现部署完成后，确认可用的 GatewayClass：

```bash
kubectl get gatewayclass
```

> [!NOTE]
> GatewayClass 名称、是否自动创建、支持哪些 Route 类型和过滤器，均取决于具体实现。迁移前应查看目标实现的 conformance 状态和官方文档。

## HTTP 路由

下面示例复用 [Ingress](./5-Ingress.md) 中的 `study-ingress` Namespace、`nginx` Deployment 和 Service。`gatewayClassName` 需要替换为集群中实际存在的 GatewayClass 名称：

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
      allowedRoutes:
        namespaces:
          from: Same
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

Gateway 的访问地址由实现写入 `status.addresses`。HTTPRoute 是否成功挂接可以在 `status.parents` 的 `Accepted` 条件中确认。与 Ingress 一样，实际访问地址取决于控制器和暴露方式。

## 常用能力

Gateway API 把 Ingress 时代常依赖私有注解的一部分能力收进结构化字段，例如请求头匹配、方法匹配、流量拆分、重定向、URL 重写和请求头修改。

按权重分流示例：

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app
  namespace: study-ingress
spec:
  parentRefs:
    - name: web-gateway
  hostnames:
    - app.example.com
  rules:
    - backendRefs:
        - name: app-stable
          port: 80
          weight: 90
        - name: app-canary
          port: 80
          weight: 10
```

请求重定向示例：

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: https-redirect
  namespace: study-ingress
spec:
  parentRefs:
    - name: web-gateway
      sectionName: http
  hostnames:
    - app.example.com
  rules:
    - filters:
        - type: RequestRedirect
          requestRedirect:
            scheme: https
            statusCode: 301
```

不同实现对扩展字段、实验字段和实现私有能力的支持不完全相同。认证、全局限流、连接池、健康检查、后端 TLS 策略等能力仍可能需要实现提供的 Policy 或 CRD。

## 迁移记录

从 Ingress 迁移到 Gateway API 时，应先明确迁移对象：

- API 迁移：把 Ingress 资源转换为 Gateway、HTTPRoute 等 Gateway API 资源。
- 控制器迁移：把 ingress-nginx 等控制器替换为仍在维护的实现。
- 数据面迁移：切换外部负载均衡、DNS、证书、真实客户端 IP 传递和观测链路。

`ingress2gateway` 可以读取集群或文件中的 Ingress 及部分控制器私有注解，输出 Gateway API 资源初稿：

```bash
ingress2gateway print --providers=ingress-nginx --all-namespaces > gateway-migration.yaml
```

工具的定位是迁移助手，不是一键替换：

- 无法翻译的注解会输出警告，例如 `configuration-snippet` 这类直接注入 NGINX 配置的注解没有 Gateway API 等价物，需要人工改写。
- 转换结果必须逐条审查并在测试环境验证，不应直接应用到生产集群。
- 路由行为存在语义差异，特别是正则路径、默认后端、转发头、超时和重定向行为。
- 推荐先并行部署新 Gateway，完成流量比对后再切换 DNS 或负载均衡指向。

## 配置建议

- 新入口优先评估 Gateway API；已有 Ingress 可以按风险和收益逐步迁移。
- Gateway API CRD 版本、实现版本和 conformance 状态应一起记录。
- 平台团队管理 GatewayClass 和 Gateway，业务团队管理 HTTPRoute，更符合多团队边界。
- 跨 Namespace 引用需要显式设计，避免把共享入口变成隐式越权通道。
- 实验字段和实现私有扩展不要写成可跨控制器迁移的通用能力。
- 迁移时保留旧入口一段时间作为回退路径，确认监控、日志和告警已经覆盖新控制器。

## 参考

- [Gateway API](https://kubernetes.io/docs/concepts/services-networking/gateway/)
- [Gateway API Getting Started](https://gateway-api.sigs.k8s.io/guides/getting-started/introduction/)
- [HTTPRoute](https://gateway-api.sigs.k8s.io/api-types/httproute/)
- [Migrating from Ingress](https://gateway-api.sigs.k8s.io/guides/getting-started/migrating-from-ingress/)
- [A Welcome Guide for Ingress-NGINX Users](https://gateway-api.sigs.k8s.io/guides/getting-started/migrating-from-ingress-nginx/)
- [Gateway API implementations](https://gateway-api.sigs.k8s.io/docs/implementations/list/)
- [Announcing Ingress2Gateway 1.0](https://kubernetes.io/blog/2026/03/20/ingress2gateway-1-0-release/)
- [ingress2gateway](https://github.com/kubernetes-sigs/ingress2gateway)
