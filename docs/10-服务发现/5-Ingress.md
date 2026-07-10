# Ingress

Ingress 是 Kubernetes 中用于声明 HTTP、HTTPS 入站路由的资源。它把来自集群外部的域名、路径和 TLS 入口映射到集群内 Service，适合承载 Web、API 网关前置入口和多域名统一发布等场景。

本文只记录 Ingress API 本身的资源边界、IngressClass、路径匹配、TLS 终止和基础排查。具体控制器实现分别放在后续页面：Traefik 的安装、Middleware、IngressRoute 和 TraefikService 见 [Traefik](./7-Traefik.md)；Gateway API 的资源模型和迁移记录见 [Gateway API](./6-GatewayAPI.md)；已退役 ingress-nginx 的存量注解见[附录：ingress-nginx](./appendix-ingress-nginx.md)。

## 入口边界

Ingress 只描述七层 HTTP、HTTPS 路由规则，本身不会直接启动代理进程，也不会自动创建外部负载均衡器。真正监听端口、接收外部请求并转发到 Service 的组件是 Ingress Controller。

常见访问链路如下：

```text
客户端 -> DNS -> 边界负载均衡器或网关 -> Ingress Controller -> Service -> Pod
```

Ingress 与其他暴露方式的边界如下：

| 资源或组件                  | 主要作用               | 典型场景                     |
|------------------------|--------------------|--------------------------|
| `ClusterIP` Service    | 集群内部稳定入口           | 服务间调用                    |
| `NodePort` Service     | 节点端口暴露四层入口         | 实验、调试或对接外部负载均衡           |
| `LoadBalancer` Service | 请求底层环境分配外部负载均衡地址   | 云环境或裸金属负载均衡实现            |
| Ingress                | HTTP、HTTPS 域名与路径路由 | 多域名、多路径、TLS 终止、统一 Web 入口 |
| Gateway API            | 更丰富的网关与流量路由 API    | 多团队网关、复杂协议和更细粒度流量治理      |

Kubernetes 官方文档建议新场景优先评估 Gateway API。Ingress API 已进入冻结状态：它仍是稳定 API，官方没有移除计划，但后续不会继续扩展新能力。现有集群中 Ingress 仍然常见，特别是 ingress-nginx、Traefik、HAProxy Ingress、Istio Gateway 等控制器已经广泛部署的环境。

## Ingress Controller

Ingress Controller 负责监听 Ingress、Service、EndpointSlice、Secret 和 IngressClass 等资源变化，并把这些声明转换成实际的数据面配置。不同控制器的实现差异较大，注解、默认行为、健康检查、TLS、转发头、灰度能力和四层扩展都需要以控制器文档为准。

可以把 Ingress 和 Ingress Controller 粗略类比为：

| Kubernetes 对象      | 近似角色        |
|--------------------|-------------|
| Ingress            | 路由配置声明      |
| Ingress Controller | 实际代理或负载均衡实现 |

只创建 Ingress 资源没有实际入口效果，集群中必须存在匹配的 Ingress Controller。本文后续示例统一使用 `traefik` 作为 IngressClass 名称，控制器安装与扩展能力见 [Traefik](./7-Traefik.md)。

## IngressClass

IngressClass 是集群级资源，用于声明某类 Ingress 应由哪个控制器处理。Ingress 通过 `spec.ingressClassName` 引用 IngressClass。

`spec.controller` 的取值由控制器定义，Traefik Helm chart 创建的 IngressClass 通常等价于：

```yaml{6}
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: traefik
spec:
  controller: traefik.io/ingress-controller
```

IngressClass 可以被标记为默认类：

```yaml{5,6}
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: traefik
  annotations:
    ingressclass.kubernetes.io/is-default-class: "true"
spec:
  controller: traefik.io/ingress-controller
```

同一集群中最多应只有一个默认 IngressClass。若多个 IngressClass 都标记为默认，未显式指定 `ingressClassName` 的 Ingress 可能被准入控制拒绝。

早期集群和部分控制器使用 `kubernetes.io/ingress.class` 注解指定控制器。当前新资源应优先使用 `spec.ingressClassName`。该字段引用的是 IngressClass 资源名称，不只是控制器进程名称。

## 资源定义

Ingress 使用 `networking.k8s.io/v1`。一个典型 Ingress 至少包含 `metadata.name`、`spec.ingressClassName`、`spec.rules`、`rules[].http.paths[]`、后端 Service 名称和端口。

下面示例包含 Namespace、Deployment、Service 和 Ingress，可作为完整资源关系参考：

```yaml [ingress-demo.yaml]
apiVersion: v1
kind: Namespace
metadata:
  name: study-ingress
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: study-ingress
spec:
  replicas: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: ingress-demo
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ingress-demo
    spec:
      containers:
        - name: nginx
          image: nginx:1.31-alpine
          ports:
            - name: http
              containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx
  namespace: study-ingress
spec:
  selector:
    app.kubernetes.io/name: ingress-demo
  ports:
    - name: http
      port: 80
      targetPort: http
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx
  namespace: study-ingress
spec:
  ingressClassName: traefik
  rules:
    - host: nginx.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nginx
                port:
                  name: http
```

首次创建资源后可以查看 Ingress 状态：

```bash
kubectl create -f ingress-demo.yaml
kubectl get ingress -n study-ingress
kubectl describe ingress nginx -n study-ingress
```

Ingress 的 `status.loadBalancer` 由控制器更新。不同控制器和暴露方式下，`ADDRESS` 可能是外部 IP、主机名、节点地址，也可能为空。NodePort 方式下可能不写回地址，应以控制器 Service 的节点端口为准确认访问入口。

本地 DNS 没有解析 `nginx.example.com` 时，可以使用 `curl --resolve` 临时把域名指向节点 IP：

```bash
curl --resolve nginx.example.com:30080:<node-ip> http://nginx.example.com:30080/
```

能看到 nginx 欢迎页即表示 Ingress 与控制器已经打通。

## 规则与路径

Ingress 规则按 Host 和 Path 匹配 HTTP 请求。Host 可省略，省略后表示该规则不限制请求的 Host 头，只按路径匹配。

Host 支持精确域名和单标签通配符：

| Host 配置           | 请求 Host              | 是否匹配 |
|-------------------|----------------------|------|
| `foo.example.com` | `foo.example.com`    | 是    |
| `*.example.com`   | `api.example.com`    | 是    |
| `*.example.com`   | `v1.api.example.com` | 否    |
| `*.example.com`   | `example.com`        | 否    |

Ingress 的 Host 字段不允许写 IP，也不允许包含端口。通配符只能作为第一个 DNS 标签单独出现，不能写成 `api*.example.com` 或 `*`。

每个 HTTP path 都必须设置 `pathType`：

| `pathType`               | 匹配方式                  | 说明                                             |
|--------------------------|-----------------------|------------------------------------------------|
| `Exact`                  | 精确匹配                  | 区分大小写，`/foo` 不匹配 `/foo/`                       |
| `Prefix`                 | 按 `/` 分隔的路径元素前缀匹配     | `/foo/bar` 匹配 `/foo/bar/baz`，不匹配 `/foo/barbaz` |
| `ImplementationSpecific` | 由 IngressClass 或控制器决定 | 常用于控制器特定语义，例如正则路径匹配                            |

多个路径同时匹配时，优先选择最长路径；如果长度相同，`Exact` 优先于 `Prefix`。需要普通前缀匹配时优先使用 `Prefix`，只有确实依赖控制器特性时再使用 `ImplementationSpecific`。

一个 Ingress 可以按路径分流到多个 Service。下面片段用于说明多路径字段关系，`web`、`api` 需替换为实际存在的 Service：

```yaml{8-25}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fanout
  namespace: study-ingress
spec:
  ingressClassName: traefik
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /web
            pathType: Prefix
            backend:
              service:
                name: web
                port:
                  number: 80
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: api
                port:
                  number: 80
```

Ingress 后端 Service 必须与 Ingress 位于同一 Namespace。跨 Namespace 暴露通常需要额外网关资源、控制器扩展能力，或在目标 Namespace 中分别声明入口。

## TLS 终止

Ingress 可以通过 `spec.tls` 引用 TLS Secret，由 Ingress Controller 在入口处完成 TLS 终止。Kubernetes Ingress API 只支持一个 TLS 端口 443；不同域名可以通过 SNI 复用同一个入口端口，前提是控制器支持。

TLS Secret 使用 `kubernetes.io/tls` 类型，数据键为 `tls.crt` 和 `tls.key`。实验环境可以生成自签名证书：

```bash
HOST=nginx.example.com
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key \
  -out tls.crt \
  -subj "/CN=${HOST}/O=${HOST}" \
  -addext "subjectAltName = DNS:${HOST}"
kubectl create secret tls nginx-tls \
  --cert=tls.crt \
  --key=tls.key \
  -n study-ingress
```

对应 Ingress：

```yaml{8-11} [ingress-tls.yaml]
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-tls
  namespace: study-ingress
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - nginx.example.com
      secretName: nginx-tls
  rules:
    - host: nginx.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nginx
                port:
                  name: http
```

通过 HTTPS 入口端口验证时，自签名证书需要 `-k` 跳过校验：

```bash
curl -k --resolve nginx.example.com:30443:<node-ip> https://nginx.example.com:30443/
```

`tls.hosts` 应与 `rules.host` 以及证书中的域名匹配。TLS 终止后，到 Service 和 Pod 的流量通常是明文 HTTP；如果后端需要 HTTPS、gRPC 或 TLS 透传，需要查看所用控制器的特定配置。是否把 HTTP 自动重定向到 HTTPS 也由控制器决定，不属于 Ingress API 的通用字段。

## 排查记录

Ingress 访问异常应从入口地址、IngressClass、路由规则、后端 Service、EndpointSlice、控制器日志和前置负载均衡器同时排查。

常用命令：

```bash
kubectl get ingress -A
kubectl describe ingress <ingress-name> -n <namespace>
kubectl get ingressclass
kubectl get svc -n <namespace>
kubectl get endpointslices -n <namespace> -l kubernetes.io/service-name=<service-name>
kubectl get events -n <namespace> --sort-by=.lastTimestamp
```

常见现象如下：

| 现象            | 可能原因                              | 检查方向                                    |
|---------------|-----------------------------------|-----------------------------------------|
| Ingress 无访问效果 | 没有安装控制器，或 `ingressClassName` 不匹配  | `kubectl get ingressclass`、控制器启动参数      |
| `ADDRESS` 为空  | 控制器未更新状态，或暴露方式不写回地址               | 控制器 Service、`status.loadBalancer`、控制器日志 |
| 404           | Host 或 Path 不匹配，后端应用路径不存在          | `rules.host`、`pathType`、控制器日志           |
| 502           | 后端协议不匹配，后端连接失败，TLS 后端配置错误         | 后端协议配置、Pod 端口、应用日志                    |
| 503           | Service 不存在、端口错误、没有可用后端端点         | Service、EndpointSlice                   |
| HTTPS 证书异常    | Secret 不存在、证书链顺序错误、证书域名与 Host 不匹配 | TLS Secret、控制器日志、SNI Host               |

排查时不要只看 Ingress YAML。Ingress 是七层路由声明，真正决定访问结果的还包括控制器部署方式、边界负载均衡器、DNS、TLS Secret、Service selector、EndpointSlice、Pod readiness、NetworkPolicy 和应用自身路由。

## 配置建议

- 新 Ingress 明确设置 `spec.ingressClassName`
- 普通路径优先使用 `Prefix` 或 `Exact`，正则路径再使用 `ImplementationSpecific`
- Ingress 后端优先引用 Service 端口名，降低端口号变更影响
- TLS Secret、Ingress 和后端 Service 放在同一 Namespace 中统一管理
- 控制器注解的值都按字符串写入，避免布尔值或数字被 YAML 解析成其他类型
- 认证、限流、重写、灰度和真实客户端 IP 处理都属于控制器扩展能力，需要查看控制器文档
- 复杂灰度、跨 Namespace 网关、多团队路由和多协议入口优先评估 Gateway API 或服务网格

## 参考

- [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Ingress Controllers](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/)
- [Ingress API reference](https://kubernetes.io/docs/reference/kubernetes-api/networking/ingress-v1/)
- [IngressClass API reference](https://kubernetes.io/docs/reference/kubernetes-api/networking/ingressclass-v1/)
- [Gateway API](https://kubernetes.io/docs/concepts/services-networking/gateway/)
