# Ingress

Ingress 是 Kubernetes 中用于声明 HTTP、HTTPS 入站路由的资源。它把来自集群外部的域名、路径和 TLS 入口映射到集群内 Service，适合承载 Web、API 网关前置入口和多域名统一发布等场景。

本文记录 Ingress 的资源边界、IngressClass、路径匹配、TLS 终止、ingress-nginx 常见扩展和排查方法。Service、EndpointSlice、DNS 和 kube-proxy 已在前文记录，Ingress 建立在这些基础能力之上。

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

Kubernetes 官方文档已明确建议新场景优先评估 Gateway API。Ingress API 已进入冻结状态：它仍是稳定 API，官方没有移除计划，但后续不会继续扩展新能力。现有集群中 Ingress 仍然常见，特别是 ingress-nginx、Traefik、HAProxy Ingress、Istio Gateway 等控制器已经广泛部署的环境。

> [!WARNING]
> ingress-nginx 项目已于 2026 年 3 月正式退役：仓库归档，不再发布新版本，也不再修复缺陷和安全漏洞；已有部署仍可继续运行，但风险会随时间累积。存量入口应规划迁移到 Gateway API 或其他仍在维护的 Ingress Controller，迁移到 Gateway API 时可评估 `ingress2gateway` 工具。F5 维护的 NGINX Ingress Controller 是另一个独立项目，不受本次退役影响。本文中的 ingress-nginx 内容保留为存量集群的参考记录，退役时间线、控制器选型和迁移路径见 [Ingress 控制器选型与 Gateway API 迁移](./6-Ingress控制器选型与GatewayAPI迁移.md)。

## Ingress Controller

Ingress Controller 负责监听 Ingress、Service、EndpointSlice、Secret 和 IngressClass 等资源变化，并把这些声明转换成实际的数据面配置。不同控制器的实现差异较大，注解、默认行为、健康检查、TLS、转发头、灰度能力和四层扩展都需要以控制器文档为准。

可以把 Ingress 和 Ingress Controller 粗略类比为：

| Kubernetes 对象      | 近似角色        |
|--------------------|-------------|
| Ingress            | 路由配置声明      |
| Ingress Controller | 实际代理或负载均衡实现 |

只创建 Ingress 资源没有实际入口效果，集群中必须存在匹配的 Ingress Controller。查看当前集群的 IngressClass 和 Ingress：

```bash
kubectl get ingressclass
kubectl get ingress --all-namespaces
kubectl describe ingress <ingress-name> -n <namespace>
```

ingress-nginx 常见安装方式包括 Helm、官方静态清单、云厂商 LoadBalancer、裸金属 NodePort、`hostPort` 或 `hostNetwork`。裸金属环境如果希望直接使用节点的 80、443 端口，常见做法是选择专用节点运行 Ingress Controller，并把外部四层负载均衡器指向这些节点。

下面片段只用于说明 `hostNetwork` 方式涉及的字段关系，不是完整 ingress-nginx 安装清单：

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
spec:
  template:
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      nodeSelector:
        kubernetes.io/os: linux
        ingress: "true"
```

对应节点可以添加专用标签：

```bash
kubectl label node <node-name> ingress=true
```

`hostNetwork` 会让控制器 Pod 使用节点网络命名空间，端口冲突、安全边界、调度位置、DNS 策略和节点防火墙都需要提前确认。生产环境更常见的是在 Ingress Controller 前面接入云负载均衡、F5、LVS、HAProxy 或其他边界网关。

## IngressClass

IngressClass 是集群级资源，用于声明某类 Ingress 应由哪个控制器处理。Ingress 通过 `spec.ingressClassName` 引用 IngressClass。

ingress-nginx 常见 IngressClass 如下：

```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx
spec:
  controller: k8s.io/ingress-nginx
```

IngressClass 可以被标记为默认类：

```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx
  annotations:
    ingressclass.kubernetes.io/is-default-class: "true"
spec:
  controller: k8s.io/ingress-nginx
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
  ingressClassName: nginx
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

应用资源后可以查看 Ingress 状态：

```bash
kubectl apply -f ingress-demo.yaml
kubectl get ingress -n study-ingress
kubectl describe ingress nginx -n study-ingress
```

Ingress 的 `status.loadBalancer` 由控制器更新。不同控制器和暴露方式下，`ADDRESS` 可能是外部 IP、主机名、节点地址，也可能为空；应结合控制器 Service 或边界负载均衡器确认真实访问地址。

如果本地 DNS 没有解析 `nginx.example.com`，可以使用 `curl --resolve` 临时指定访问地址：

```bash
curl --resolve nginx.example.com:80:<ingress-address> http://nginx.example.com/
```

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
| `ImplementationSpecific` | 由 IngressClass 或控制器决定 | 常用于控制器特定语义，例如 ingress-nginx 正则路径               |

多个路径同时匹配时，优先选择最长路径；如果长度相同，`Exact` 优先于 `Prefix`。需要普通前缀匹配时优先使用 `Prefix`，只有确实依赖控制器特性时再使用 `ImplementationSpecific`。

一个 Ingress 可以按路径分流到多个 Service：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fanout
  namespace: study-ingress
spec:
  ingressClassName: nginx
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

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-tls
  namespace: study-ingress
spec:
  ingressClassName: nginx
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

`tls.hosts` 应与 `rules.host` 以及证书中的域名匹配。TLS 终止后，到 Service 和 Pod 的流量通常是明文 HTTP；如果后端需要 HTTPS、gRPC 或 TLS 透传，需要查看所用控制器的特定配置。

ingress-nginx 中，配置了 TLS 块时默认会把 HTTP 重定向到 HTTPS，默认重定向状态码为 308。是否启用重定向、是否使用默认证书、是否启用 SSL Passthrough 都属于 ingress-nginx 控制器配置范围，不是 Ingress API 的通用字段。

## ingress-nginx 扩展

以下内容只适用于 ingress-nginx。其他 Ingress Controller 可能使用完全不同的注解、CRD 或配置入口。ingress-nginx 已退役，这些注解仅作为存量集群的维护参考，新入口不应再基于 ingress-nginx 设计。

ingress-nginx 注解默认前缀为 `nginx.ingress.kubernetes.io`。注解的键和值都是字符串，布尔值和数字也应加引号，例如 `"true"`、`"120"`。

### Basic Auth

ingress-nginx 可以通过 htpasswd 文件和 Secret 为某个 Ingress 增加 HTTP Basic Auth。Secret 中的键必须是 `auth`，否则控制器会返回 503。

创建认证文件和 Secret：

```bash
htpasswd -c auth foo
kubectl create secret generic basic-auth \
  --from-file=auth \
  -n study-ingress
```

带认证的 Ingress 示例：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-auth
  namespace: study-ingress
  annotations:
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: basic-auth
    nginx.ingress.kubernetes.io/auth-realm: "Authentication Required"
spec:
  ingressClassName: nginx
  rules:
    - host: auth.example.com
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

这类认证适合临时保护不自带登录能力的内部工具。面向生产用户的身份认证通常应由统一身份系统、网关认证插件或应用自身处理。

### 会话保持

Service 的 `sessionAffinity: ClientIP` 是四层源 IP 粘性。ingress-nginx 可以使用 Cookie 做七层会话保持：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-sticky
  namespace: study-ingress
  annotations:
    nginx.ingress.kubernetes.io/affinity: "cookie"
    nginx.ingress.kubernetes.io/affinity-mode: "balanced"
    nginx.ingress.kubernetes.io/session-cookie-name: "INGRESSCOOKIE"
    nginx.ingress.kubernetes.io/session-cookie-expires: "172800"
    nginx.ingress.kubernetes.io/session-cookie-max-age: "172800"
spec:
  ingressClassName: nginx
  rules:
    - host: sticky.example.com
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

`affinity-mode: balanced` 会在后端扩容时重新分布部分会话，`persistent` 更偏向最大粘性。若 Ingress 使用正则路径，还需要设置 `nginx.ingress.kubernetes.io/session-cookie-path`，因为 Cookie path 不支持正则。

### Rewrite

当外部路径与后端应用实际路径不一致时，可以使用 rewrite。ingress-nginx v0.22.0 之后，所有需要保留到重写目标的路径片段都必须显式写入捕获组。

下面示例把 `/api-a` 前缀去掉后转发到后端：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-rewrite
  namespace: study-ingress
  annotations:
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  rules:
    - host: rewrite.example.com
      http:
        paths:
          - path: /api-a(/|$)(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: nginx
                port:
                  name: http
```

匹配效果如下：

| 请求路径          | 后端收到路径  |
|---------------|---------|
| `/api-a`      | `/`     |
| `/api-a/`     | `/`     |
| `/api-a/test` | `/test` |

ingress-nginx 中，如果同一 host 下任意 Ingress 使用 `use-regex` 或 `rewrite-target`，该 host 的所有路径都会按正则 location 方式生成。重写路径和普通路径混放时容易出现匹配优先级偏差，应尽量拆分 host 或清晰隔离路径规则。

### Redirect

永久重定向可以通过 `permanent-redirect` 配置：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-redirect
  namespace: study-ingress
  annotations:
    nginx.ingress.kubernetes.io/permanent-redirect: "https://new.example.com$request_uri"
    nginx.ingress.kubernetes.io/permanent-redirect-code: "308"
spec:
  ingressClassName: nginx
  rules:
    - host: old.example.com
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

ingress-nginx 也支持临时重定向、`www` 与非 `www` 之间重定向、强制 HTTPS 重定向等配置。域名迁移、接口路径迁移和 HTTPS 规范化应结合缓存、SEO、客户端兼容和回滚策略处理。

### 限流与访问控制

ingress-nginx 支持按 Ingress 配置连接数、请求速率和来源地址限制：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-limit
  namespace: study-ingress
  annotations:
    nginx.ingress.kubernetes.io/limit-connections: "10"
    nginx.ingress.kubernetes.io/limit-rps: "5"
    nginx.ingress.kubernetes.io/whitelist-source-range: "192.0.2.0/24,198.51.100.10"
spec:
  ingressClassName: nginx
  rules:
    - host: limit.example.com
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

常见注解如下：

| 注解                                                   | 说明               |
|------------------------------------------------------|------------------|
| `nginx.ingress.kubernetes.io/limit-connections`      | 限制单个客户端 IP 并发连接数 |
| `nginx.ingress.kubernetes.io/limit-rps`              | 限制单个客户端 IP 每秒请求数 |
| `nginx.ingress.kubernetes.io/denylist-source-range`  | 拒绝指定 CIDR 或 IP   |
| `nginx.ingress.kubernetes.io/whitelist-source-range` | 只允许指定 CIDR 或 IP  |

连接数和请求速率限制都以单个客户端 IP 为对象、按控制器副本分别计数，多副本部署时实际放行总量会成倍放大；超过限制时默认返回 503。

来源 IP 是否真实取决于前置负载均衡器、PROXY protocol、`X-Forwarded-For` 信任配置和 `externalTrafficPolicy`。如果 Ingress Controller 看到的都是上游负载均衡器 IP，限流和黑白名单会集中作用在同一个源地址上。

### CORS

跨域响应头可以通过 ingress-nginx 注解生成：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-cors
  namespace: study-ingress
  annotations:
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-origin: "https://app.example.com"
    nginx.ingress.kubernetes.io/cors-allow-methods: "GET, POST, PUT, DELETE, OPTIONS"
    nginx.ingress.kubernetes.io/cors-allow-headers: "Authorization, Content-Type"
spec:
  ingressClassName: nginx
  rules:
    - host: api.example.com
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

CORS 是浏览器安全模型的一部分，不是后端访问控制。允许所有来源时需要谨慎，尤其是涉及 Cookie、Token 或管理接口的服务。

### 长连接与流式响应

SSE、长轮询或响应耗时较长的接口，通常需要调整代理缓冲和超时：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-streaming
  namespace: study-ingress
  annotations:
    nginx.ingress.kubernetes.io/proxy-http-version: "1.1"
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
spec:
  ingressClassName: nginx
  rules:
    - host: stream.example.com
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

更复杂的 NGINX 片段可以通过 `configuration-snippet` 插入到 location 配置中，但这类能力风险较高，是否允许通常由集群管理员控制。多租户集群中不应默认开放任意 snippet 注解。

### Canary

ingress-nginx 可以用两个 Ingress 对同一 host 和 path 做金丝雀路由。主 Ingress 指向稳定版本，Canary Ingress 指向新版本，并添加 canary 注解：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app
  namespace: study-ingress
spec:
  ingressClassName: nginx
  rules:
    - host: canary.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app-stable
                port:
                  number: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-canary
  namespace: study-ingress
  annotations:
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-weight: "10"
spec:
  ingressClassName: nginx
  rules:
    - host: canary.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app-canary
                port:
                  number: 80
```

Canary 条件有优先级：header 高于 cookie，cookie 高于权重。当前 ingress-nginx 对同一 Ingress 规则最多应用一个 Canary Ingress。更复杂的蓝绿、灰度、流量镜像和基于请求属性的路由，通常更适合 Gateway API、服务网格或专门的发布系统。

### 自定义错误页

ingress-nginx 默认后端会处理未匹配的 host 或 path。自定义错误页可以通过控制器默认后端、`custom-http-errors` 和 `default-backend` 注解组合实现。

按 Ingress 指定需要拦截的错误码：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-errors
  namespace: study-ingress
  annotations:
    nginx.ingress.kubernetes.io/custom-http-errors: "404,502,503"
    nginx.ingress.kubernetes.io/default-backend: error-pages
spec:
  ingressClassName: nginx
  rules:
    - host: errors.example.com
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

`default-backend` 注解引用同 Namespace 中的 Service。自定义错误后端应返回真实错误状态码，而不是统一返回 200，否则会影响调用方、监控和搜索引擎对错误的判断。

## 排查记录

Ingress 访问异常应从入口地址、IngressClass、路由规则、后端 Service、EndpointSlice、控制器日志和前置负载均衡器同时排查。

常用命令：

```bash
kubectl get ingress -A
kubectl describe ingress <ingress-name> -n <namespace>
kubectl get ingressclass
kubectl get svc -n <namespace>
kubectl get endpointslices -n <namespace> -l kubernetes.io/service-name=<service-name>
kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=100
kubectl get events -n <namespace> --sort-by=.lastTimestamp
```

常见现象如下：

| 现象            | 可能原因                                                 | 检查方向                                                        |
|---------------|------------------------------------------------------|-------------------------------------------------------------|
| Ingress 无访问效果 | 没有安装控制器，或 `ingressClassName` 不匹配                     | `kubectl get ingressclass`、控制器启动参数                          |
| `ADDRESS` 为空  | 控制器未更新状态，或暴露方式不写回地址                                  | 控制器 Service、`status.loadBalancer`、控制器日志                     |
| 404           | Host 或 Path 不匹配，默认后端响应，后端应用路径不存在                     | `rules.host`、`pathType`、rewrite 配置                          |
| 401           | Basic Auth、外部认证或应用认证拦截                               | 认证注解、Secret、认证服务日志                                          |
| 413           | 请求体超过控制器限制                                           | `nginx.ingress.kubernetes.io/proxy-body-size` 或全局 ConfigMap |
| 502           | 后端协议不匹配，后端连接失败，TLS 后端配置错误                            | `backend-protocol`、Pod 端口、应用日志                              |
| 503           | Service 不存在、端口错误、没有可用 Endpoint、Basic Auth Secret 键错误 | Service、EndpointSlice、Secret 键名                             |
| 504           | 后端处理超时或连接超时                                          | `proxy-read-timeout`、`proxy-send-timeout`、应用耗时              |
| HTTPS 证书异常    | Secret 不存在、证书链顺序错误、证书域名与 Host 不匹配                    | TLS Secret、控制器日志、SNI Host                                   |
| 黑白名单不生效       | 控制器看到的源 IP 不是客户端真实 IP                                | 前置 LB、PROXY protocol、转发头信任配置                                |

排查时不要只看 Ingress YAML。Ingress 是七层路由声明，真正决定访问结果的还包括控制器部署方式、边界负载均衡器、DNS、TLS Secret、Service selector、EndpointSlice、Pod readiness、NetworkPolicy 和应用自身路由。

## 配置建议

- 新 Ingress 明确设置 `spec.ingressClassName`
- 普通路径优先使用 `Prefix` 或 `Exact`，正则路径再使用 `ImplementationSpecific`
- Ingress 后端优先引用 Service 端口名，降低端口号变更影响
- TLS Secret、Ingress 和后端 Service 放在同一 Namespace 中统一管理
- ingress-nginx 注解都按字符串写入，避免布尔值或数字被 YAML 解析成其他类型
- rewrite、regex 和普通路径不要随意混放在同一 host 下
- Basic Auth 只作为轻量保护，不替代完整身份认证体系
- 限流、黑白名单依赖真实客户端 IP，应先确认前置负载均衡与转发头配置
- 复杂灰度、跨 Namespace 网关、多团队路由和多协议入口优先评估 Gateway API 或服务网格
- 控制器安装和升级以所选控制器官方文档为准，不直接复制旧版本清单
- 仍在使用 ingress-nginx 的集群应制定迁移计划，优先评估 Gateway API 或其他维护中的控制器

## 参考

本文内容参考以下 Kubernetes 英文文档、API Reference、kubectl 参考和 ingress-nginx 官方文档：

- [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Gateway API](https://kubernetes.io/docs/concepts/services-networking/gateway/)
- [Ingress NGINX Retirement: What You Need to Know](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/)
- [Ingress NGINX: Statement from the Kubernetes Steering and Security Response Committees](https://kubernetes.io/blog/2026/01/29/ingress-nginx-statement/)
- [Ingress API reference](https://kubernetes.io/docs/reference/kubernetes-api/networking/ingress-v1/)
- [IngressClass API reference](https://kubernetes.io/docs/reference/kubernetes-api/networking/ingressclass-v1/)
- [kubectl create ingress](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_ingress/)
- [ingress-nginx Installation Guide](https://kubernetes.github.io/ingress-nginx/deploy/)
- [ingress-nginx Annotations](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/)
- [ingress-nginx Basic usage](https://kubernetes.github.io/ingress-nginx/user-guide/basic-usage/)
- [ingress-nginx TLS/HTTPS](https://kubernetes.github.io/ingress-nginx/user-guide/tls/)
- [ingress-nginx Ingress Path Matching](https://kubernetes.github.io/ingress-nginx/user-guide/ingress-path-matching/)
- [ingress-nginx Basic Authentication](https://kubernetes.github.io/ingress-nginx/examples/auth/basic/)
- [ingress-nginx Rewrite](https://kubernetes.github.io/ingress-nginx/examples/rewrite/)
- [ingress-nginx Sticky Sessions](https://kubernetes.github.io/ingress-nginx/examples/affinity/cookie/)
- [ingress-nginx Canary Deployments](https://kubernetes.github.io/ingress-nginx/examples/canary/)
- [ingress-nginx Custom errors](https://kubernetes.github.io/ingress-nginx/user-guide/custom-errors/)
- [ingress-nginx Default backend](https://kubernetes.github.io/ingress-nginx/user-guide/default-backend/)
