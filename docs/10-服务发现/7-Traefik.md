# Traefik

Traefik 是可运行在 Kubernetes 中的入口控制器和反向代理。它既可以作为 Ingress Controller 处理 `networking.k8s.io/v1` Ingress，也可以作为 Gateway API 实现处理 Gateway、HTTPRoute 等资源；本文集中记录本章示例所用的 Traefik 部署、IngressClass、Middleware、IngressRoute、TraefikService 和排查要点。

Ingress API 本身的字段、路径匹配和 TLS 终止见 [Ingress](./5-Ingress.md)，Gateway API 资源模型见 [Gateway API](./6-GatewayAPI.md)，已退役 ingress-nginx 的存量注解示例见[附录：ingress-nginx](./appendix-ingress-nginx.md)。Service、EndpointSlice、DNS 和 kube-proxy 已在前文记录，Traefik 建立在这些基础能力之上。


## 控制器定位

Traefik 在本章中承担 Ingress Controller 和后续 Gateway API 实现的角色。Ingress 资源只负责声明 Host、Path、TLS 和后端 Service，Traefik 负责监听这些资源并把它们转换成实际的数据面路由。

Traefik 的 Kubernetes 集成主要有三类入口：

| 入口 | 说明 |
| --- | --- |
| Ingress | 读取 Kubernetes 原生 Ingress 资源，适合保持通用 API |
| Gateway API | 读取 Gateway、HTTPRoute 等资源，适合新入口设计 |
| Traefik CRD | 读取 Middleware、IngressRoute、TraefikService 等资源，表达 Traefik 私有能力 |

本文示例以 Ingress + Traefik CRD 为主：通用路由仍放在 Ingress 中，认证、限流、重写、灰度等能力通过 Middleware、IngressRoute 或 TraefikService 补充。

## 部署实验控制器

Traefik 官方提供 Helm chart。实验集群没有 LoadBalancer 实现，把控制器 Service 固定为 NodePort，便于用节点 IP 直接访问：

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm install traefik traefik/traefik \
  --namespace traefik --create-namespace \
  --set service.type=NodePort \
  --set ports.web.nodePort=30080 \
  --set ports.websecure.nodePort=30443
```

chart 会一并安装 Traefik 的 CRD（Middleware、IngressRoute、TraefikService 等），并创建名为 `traefik` 的 IngressClass。`web`、`websecure` 是 Traefik 的两个入口点，分别对应 HTTP 和 HTTPS，上面的安装参数把它们固定在节点的 30080 和 30443 端口。

确认控制器就绪和 IngressClass 存在：

```bash
kubectl get pods -n traefik
kubectl get ingressclass
```

::: details 输出类似如下

```text
NAME                       READY   STATUS    RESTARTS   AGE
traefik-6bd9d8b9c5-x2m7k   1/1     Running   0          1m

NAME      CONTROLLER                      PARAMETERS   AGE
traefik   traefik.io/ingress-controller   <none>       1m
```

:::

后续示例统一通过 `http://<域名>:30080` 访问，`<node-ip>` 用任一节点 IP 替换即可。生产环境更常见的是在控制器前面接入云负载均衡、F5、LVS、HAProxy 或其他边界网关，或者选择专用节点用 `hostNetwork` 直接占用 80、443 端口；`hostNetwork` 会让控制器 Pod 使用节点网络命名空间，端口冲突、安全边界、调度位置、DNS 策略和节点防火墙都需要提前确认。


## 示例前提

后续示例复用 [Ingress](./5-Ingress.md) 中的 `study-ingress` Namespace、Nginx Deployment 和 Nginx Service。若只阅读 Traefik 扩展能力，可先应用该页的 `ingress-demo.yaml`，再继续本页的 Middleware、IngressRoute 和 TraefikService 示例。

## Traefik 功能扩展

Ingress API 只覆盖 Host、Path 和 TLS 终止。认证、限流、重写、灰度、会话保持等能力由各控制器扩展提供，注解不能跨控制器平移。ingress-nginx 时代这些能力通过 `nginx.ingress.kubernetes.io/*` 注解表达（见附录）；Traefik 的做法是把每种能力定义成 Middleware CRD 对象，再用一个注解挂到 Ingress 上：

```yaml
metadata:
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: <namespace>-<middleware-name>@kubernetescrd
```

引用格式是「Middleware 所在 Namespace + `-` + Middleware 名称 + `@kubernetescrd`」，多个中间件用逗号分隔、从左到右依次生效。本文的 Middleware 都创建在 `study-ingress` 中，因此引用前缀固定为 `study-ingress-`。多个 Ingress 需要复用同一组中间件时，可以先用 `chain` 中间件把它们组合成一个可复用单元，注解里只引用这一个组合。

Gateway API 把其中最常用的能力（路径重写、重定向、按权重分流、请求头修改）收进了 HTTPRoute 的标准字段，不再依赖控制器私有扩展。

### Basic Auth

Traefik 通过 `basicAuth` 中间件实现 HTTP Basic Auth，用户数据来自 Secret，Secret 中的键必须是 `users`，内容为 htpasswd 格式。

创建认证文件和 Secret：

```bash
htpasswd -c auth foo
kubectl create secret generic basic-auth \
  --from-file=users=auth \
  -n study-ingress
```

创建 Middleware 和带认证的 Ingress：

```yaml [ingress-auth.yaml]
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: basic-auth
  namespace: study-ingress
spec:
  basicAuth:
    secret: basic-auth
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-auth
  namespace: study-ingress
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: study-ingress-basic-auth@kubernetescrd
spec:
  ingressClassName: traefik
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

验证未认证请求返回 401、带凭据请求正常：

```bash
curl -s -o /dev/null -w "%{http_code}\n" --resolve auth.example.com:30080:<node-ip> http://auth.example.com:30080/
curl -s -o /dev/null -w "%{http_code}\n" -u foo:<password> --resolve auth.example.com:30080:<node-ip> http://auth.example.com:30080/
```

这类认证适合临时保护不自带登录能力的内部工具。面向生产用户的身份认证通常应由统一身份系统、网关认证插件或应用自身处理。

### 外部认证

`forwardAuth` 把认证决策委托给外部服务：每个请求先被转发到认证服务，认证服务返回 2XX 时放行原请求，否则把认证服务的响应（例如 302 跳转登录页、401）直接返回给客户端。这是对接 oauth2-proxy、Authelia、authentik 等统一认证组件的标准方式，对应 ingress-nginx 时代的 `auth-url` 注解：

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: forward-auth
  namespace: study-ingress
spec:
  forwardAuth:
    address: http://oauth2-proxy.auth.svc.cluster.local:4180/oauth2/auth
    trustForwardHeader: true
    authResponseHeaders:
      - X-Auth-Request-User
      - X-Auth-Request-Email
```

`address` 指向集群内实际部署的认证服务，本示例假设 `auth` Namespace 中已部署 oauth2-proxy，未部署认证服务时该中间件会拦截所有请求。`authResponseHeaders` 声明把认证服务响应中的哪些头复制给后端请求，后端应用据此获取用户身份；`trustForwardHeader` 控制是否信任传入的 `X-Forwarded-*` 头，应配合入口点的 `forwardedHeaders.trustedIPs` 一起使用，避免客户端伪造来源信息。挂载方式与 Basic Auth 相同，注解改引用 `study-ingress-forward-auth@kubernetescrd` 即可。

### 会话保持

Service 的 `sessionAffinity: ClientIP` 是四层源 IP 粘性。Traefik 可以基于 Cookie 做七层会话保持，配置方式是给后端 Service 添加注解（注意是 Service，不是 Ingress）：

```yaml [service-sticky.yaml]
apiVersion: v1
kind: Service
metadata:
  name: nginx-sticky
  namespace: study-ingress
  annotations:
    traefik.ingress.kubernetes.io/service.sticky.cookie: "true"
    traefik.ingress.kubernetes.io/service.sticky.cookie.name: "INGRESSCOOKIE"
    traefik.ingress.kubernetes.io/service.sticky.cookie.httponly: "true"
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
  name: nginx-sticky
  namespace: study-ingress
spec:
  ingressClassName: traefik
  rules:
    - host: sticky.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nginx-sticky
                port:
                  name: http
```

首次访问时响应会携带 `Set-Cookie: INGRESSCOOKIE=...`，后续请求带上该 Cookie 就会固定路由到同一个 Pod：

```bash
curl -sv --resolve sticky.example.com:30080:<node-ip> http://sticky.example.com:30080/ 2>&1 | grep -i set-cookie
```

被固定的 Pod 因发布或缩容消失后，会话会重新分配到其他后端，应用不应把关键状态只寄存在「同一后端」这一假设上。

### Rewrite

当外部路径与后端应用实际路径不一致时，可以在转发前改写路径。去掉固定前缀用 `stripPrefix`：

```yaml [ingress-rewrite.yaml]
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: strip-api-a
  namespace: study-ingress
spec:
  stripPrefix:
    prefixes:
      - /api-a
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-rewrite
  namespace: study-ingress
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: study-ingress-strip-api-a@kubernetescrd
spec:
  ingressClassName: traefik
  rules:
    - host: rewrite.example.com
      http:
        paths:
          - path: /api-a
            pathType: Prefix
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

`curl --resolve rewrite.example.com:30080:<node-ip> http://rewrite.example.com:30080/api-a` 返回 nginx 欢迎页（后端收到 `/`），即验证重写生效。

更复杂的改写用 `replacePathRegex` 表达正则捕获组替换：

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: replace-path
  namespace: study-ingress
spec:
  replacePathRegex:
    regex: ^/api-a/(.*)
    replacement: /$1
```

重写只改变转发到后端的路径，浏览器地址栏不变。后端返回的重定向 Location、页面内的绝对路径引用不会被自动改写，是这类配置最常见的踩坑点。

### Redirect

跨域名的永久重定向用 `redirectRegex`：

```yaml [ingress-redirect.yaml]
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: redirect-new
  namespace: study-ingress
spec:
  redirectRegex:
    regex: ^https?://old.example.com/(.*)
    replacement: https://new.example.com/${1}
    permanent: true
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-redirect
  namespace: study-ingress
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: study-ingress-redirect-new@kubernetescrd
spec:
  ingressClassName: traefik
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

HTTP 到 HTTPS 的重定向用 `redirectScheme`；实验环境 HTTPS 走的是 30443 节点端口，需要显式指定端口，生产环境标准 443 端口则省略 `port`：

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: https-redirect
  namespace: study-ingress
spec:
  redirectScheme:
    scheme: https
    permanent: true
    port: "30443"
```

域名迁移、接口路径迁移和 HTTPS 规范化应结合缓存、SEO、客户端兼容和回滚策略处理。

### 限流与访问控制

`rateLimit` 按客户端来源限制请求速率，`ipAllowList` 限制来源地址；两个中间件可以逗号分隔同时挂到一个 Ingress：

```yaml [ingress-limit.yaml]
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: rate-limit
  namespace: study-ingress
spec:
  rateLimit:
    average: 5
    burst: 10
    period: 1s
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: ip-allow
  namespace: study-ingress
spec:
  ipAllowList:
    sourceRange:
      - 192.0.2.0/24
      - 198.51.100.10/32
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-limit
  namespace: study-ingress
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: study-ingress-rate-limit@kubernetescrd,study-ingress-ip-allow@kubernetescrd
spec:
  ingressClassName: traefik
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

`average` 与 `period` 共同定义平均速率（本例每秒 5 个请求），`burst` 允许的瞬时突发量。超过限制返回 429，不在允许名单内的来源返回 403。用循环请求可以直接观察到限流生效：

```bash
for i in $(seq 1 30); do
  curl -s -o /dev/null -w "%{http_code} " --resolve limit.example.com:30080:<node-ip> http://limit.example.com:30080/
done; echo
```

`rateLimit` 限制的是请求速率，并发维度对应 `inFlightReq`：单个来源同时在途的请求数超过 `amount` 时返回 429，等价于 ingress-nginx 的 `limit-connections`，适合保护慢接口和连接数敏感的后端：

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: limit-conn
  namespace: study-ingress
spec:
  inFlightReq:
    amount: 10
```

挂载方式相同，把 `study-ingress-limit-conn@kubernetescrd` 追加到注解列表即可；默认按客户端 IP 归类来源，可用 `sourceCriterion` 改为按请求头等其他维度归类。

两点与 ingress-nginx 时代相同的注意事项仍然成立：限流计数按控制器副本独立进行，多副本部署时实际放行总量会成倍放大；限流和黑白名单作用的都是控制器看到的来源 IP，控制器前面还有负载均衡器时，需要用 `ipStrategy`（基于 `X-Forwarded-For` 的深度取值）等配置还原真实客户端 IP，否则所有请求会被算在同一个源地址上。

### CORS

跨域响应头通过 `headers` 中间件生成，配置后预检请求（OPTIONS）由 Traefik 直接应答，不再转发到后端：

```yaml [ingress-cors.yaml]
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: cors
  namespace: study-ingress
spec:
  headers:
    accessControlAllowOriginList:
      - https://app.example.com
    accessControlAllowMethods:
      - GET
      - POST
      - PUT
      - DELETE
      - OPTIONS
    accessControlAllowHeaders:
      - Authorization
      - Content-Type
    accessControlMaxAge: 100
    addVaryHeader: true
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-cors
  namespace: study-ingress
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: study-ingress-cors@kubernetescrd
spec:
  ingressClassName: traefik
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

`accessControlAllowOriginList` 按精确值匹配请求的 `Origin` 头，需要模式匹配时改用 `accessControlAllowOriginListRegex`。注意在 Traefik 侧启用 CORS 后，后端自行设置的 `Access-Control-Allow-Origin` 会被覆盖，应避免两侧同时管理。CORS 是浏览器安全模型的一部分，不是后端访问控制。允许所有来源时需要谨慎，尤其是涉及 Cookie、Token 或管理接口的服务。

`headers` 中间件同时也是配置安全响应头的入口：HSTS（`stsSeconds` 等字段）、自定义请求头和响应头（`customRequestHeaders`、`customResponseHeaders`）都由它承载，可以与 CORS 配置写在同一个 Middleware 中。

### 请求体限制与流式响应

Traefik 默认不缓冲请求和响应，SSE、长轮询这类流式接口开箱即用，不需要像 ingress-nginx 那样显式关闭代理缓冲。需要限制请求体大小时使用 `buffering` 中间件，超限返回 413：

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: limit-body
  namespace: study-ingress
spec:
  buffering:
    maxRequestBodyBytes: 2000000
```

注意 `buffering` 会为了检查大小而缓冲请求体，只应挂在确实需要限制的上传入口上。响应耗时较长的接口还受入口点读写超时约束，相关配置是静态配置中的 `entryPoints.<name>.transport.respondingTimeouts`（`readTimeout`、`writeTimeout`、`idleTimeout`），可通过 Helm values 的 `additionalArguments` 调整，属于控制器全局配置而不是按 Ingress 的配置。

### HTTPS 后端

Traefik 到后端默认走明文 HTTP。后端本身以 HTTPS 提供服务时，满足以下任一条件 Traefik 就会改用 TLS 连接后端：Service 端口号为 443、端口名以 `https` 开头，或在 Service 上显式添加协议注解（值为 `h2c` 时表示明文 HTTP/2，常见于 gRPC 后端）：

```yaml
metadata:
  annotations:
    traefik.ingress.kubernetes.io/service.serversscheme: https
```

后端使用自签名证书时，直接连接会因证书校验失败得到 502，需要再配一个 `ServersTransport` 声明校验行为，并在 Service 上引用。下面片段用于说明注解与 `ServersTransport` 的引用关系，后端需自行提供 443 端口的 TLS 服务：

```yaml
apiVersion: traefik.io/v1alpha1
kind: ServersTransport
metadata:
  name: skip-verify
  namespace: study-ingress
spec:
  insecureSkipVerify: true
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-https
  namespace: study-ingress
  annotations:
    traefik.ingress.kubernetes.io/service.serversscheme: https
    traefik.ingress.kubernetes.io/service.serverstransport: study-ingress-skip-verify@kubernetescrd
spec:
  selector:
    app.kubernetes.io/name: ingress-demo
  ports:
    - name: https
      port: 443
      targetPort: 443
```

> [!CAUTION]
> `insecureSkipVerify: true` 会放弃对后端证书的一切校验，只适合实验环境或受控内网。生产环境应为后端签发可信证书，或通过 `ServersTransport` 的 `rootCAs` 字段信任私有 CA。

### 弹性与压缩

三个开销很低、生产常开的中间件可以按需组合。`compress` 根据请求的 `Accept-Encoding` 自动压缩响应（gzip、brotli、zstd）；`retry` 在与后端建立连接失败等网络层错误时按指数退避重发请求；`circuitBreaker` 按表达式统计后端健康状况，触发后短路请求、默认直接返回 503，恢复期通过试探流量逐步闭合：

```yaml [resilience.yaml]
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: compress
  namespace: study-ingress
spec:
  compress: {}
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: retry
  namespace: study-ingress
spec:
  retry:
    attempts: 3
    initialInterval: 100ms
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: circuit-breaker
  namespace: study-ingress
spec:
  circuitBreaker:
    expression: "NetworkErrorRatio() > 0.30 || ResponseCodeRatio(500, 600, 0, 600) > 0.50"
```

挂到 Ingress 时按注解中的逗号顺序生效，例如 `study-ingress-retry@kubernetescrd,study-ingress-circuit-breaker@kubernetescrd`。两点注意：`retry` 会完整重发请求，非幂等接口（下单、扣款类）要谨慎开启；熔断器只统计位于它之后的链路情况，应放在中间件链的靠后位置。

### 自定义错误页

`errors` 中间件在后端返回指定状态码时改由错误页服务响应。错误页本身需要一个真实的后端来提供，下面用 ConfigMap 加 nginx 部署一个最简错误页服务，并把 404、502、503 指向它：

```yaml [error-pages.yaml]
apiVersion: v1
kind: ConfigMap
metadata:
  name: error-pages
  namespace: study-ingress
data:
  404.html: "<h1>Page Not Found</h1>"
  502.html: "<h1>Bad Gateway</h1>"
  503.html: "<h1>Service Unavailable</h1>"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: error-pages
  namespace: study-ingress
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: error-pages
  template:
    metadata:
      labels:
        app.kubernetes.io/name: error-pages
    spec:
      containers:
        - name: nginx
          image: nginx:1.31-alpine
          ports:
            - name: http
              containerPort: 80
          volumeMounts:
            - name: pages
              mountPath: /usr/share/nginx/html
      volumes:
        - name: pages
          configMap:
            name: error-pages
---
apiVersion: v1
kind: Service
metadata:
  name: error-pages
  namespace: study-ingress
spec:
  selector:
    app.kubernetes.io/name: error-pages
  ports:
    - name: http
      port: 80
      targetPort: http
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: custom-errors
  namespace: study-ingress
spec:
  errors:
    status:
      - "404"
      - "502"
      - "503"
    service:
      name: error-pages
      port: 80
    query: "/{status}.html"
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-errors
  namespace: study-ingress
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: study-ingress-custom-errors@kubernetescrd
spec:
  ingressClassName: traefik
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

访问一个后端不存在的路径即可验证，响应体来自错误页服务、状态码保持触发时的原始值：

```bash
curl -s --resolve errors.example.com:30080:<node-ip> http://errors.example.com:30080/no-such-page
```

`status` 支持单个状态码和 `500-599` 这样的闭区间。自定义错误后端应返回真实错误状态码语义的内容，而不是把错误包装成正常页面，否则会影响调用方、监控和搜索引擎对错误的判断。

### Canary

Ingress API 本身无法表达按权重分流，ingress-nginx 通过双 Ingress 加 canary 注解实现（见附录），Traefik 则通过 `TraefikService` 的加权轮询实现，路由入口需要换用 Traefik 的 IngressRoute CRD。

先部署稳定版和灰度版两组后端，使用 `traefik/whoami` 便于从响应中直接看出请求落在哪个版本：

```yaml [canary-backends.yaml]
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-stable
  namespace: study-ingress
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: canary-demo
      app.kubernetes.io/version: stable
  template:
    metadata:
      labels:
        app.kubernetes.io/name: canary-demo
        app.kubernetes.io/version: stable
    spec:
      containers:
        - name: whoami
          image: traefik/whoami:v1.11
          ports:
            - name: http
              containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: app-stable
  namespace: study-ingress
spec:
  selector:
    app.kubernetes.io/name: canary-demo
    app.kubernetes.io/version: stable
  ports:
    - name: http
      port: 80
      targetPort: http
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-canary
  namespace: study-ingress
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: canary-demo
      app.kubernetes.io/version: canary
  template:
    metadata:
      labels:
        app.kubernetes.io/name: canary-demo
        app.kubernetes.io/version: canary
    spec:
      containers:
        - name: whoami
          image: traefik/whoami:v1.11
          ports:
            - name: http
              containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: app-canary
  namespace: study-ingress
spec:
  selector:
    app.kubernetes.io/name: canary-demo
    app.kubernetes.io/version: canary
  ports:
    - name: http
      port: 80
      targetPort: http
```

再声明 9:1 的加权服务和路由：

```yaml [canary-route.yaml]
apiVersion: traefik.io/v1alpha1
kind: TraefikService
metadata:
  name: app-weighted
  namespace: study-ingress
spec:
  weighted:
    services:
      - name: app-stable
        port: 80
        weight: 90
      - name: app-canary
        port: 80
        weight: 10
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: app
  namespace: study-ingress
spec:
  entryPoints:
    - web
  routes:
    - match: Host(`canary.example.com`)
      kind: Rule
      services:
        - name: app-weighted
          kind: TraefikService
```

whoami 会输出所在 Pod 的 Hostname，循环请求可以观察到大约 10% 的请求落在 `app-canary`：

```bash
for i in $(seq 1 20); do
  curl -s --resolve canary.example.com:30080:<node-ip> http://canary.example.com:30080/ | grep Hostname
done
```

这一步已经离开了 Ingress API 的表达范围，是控制器私有 CRD 在补位。Gateway API 把按权重分流做成了 HTTPRoute 的标准字段（`backendRefs[].weight`），是新场景下更值得优先评估的写法。更复杂的蓝绿、流量镜像和基于请求属性的路由，通常更适合 Gateway API、服务网格或专门的发布系统。

## 排查记录

Ingress 访问异常应从入口地址、IngressClass、路由规则、后端 Service、EndpointSlice、控制器日志和前置负载均衡器同时排查。

常用命令：

```bash
kubectl get ingress -A
kubectl describe ingress <ingress-name> -n <namespace>
kubectl get ingressclass
kubectl get middleware -n <namespace>
kubectl get svc -n <namespace>
kubectl get endpointslices -n <namespace> -l kubernetes.io/service-name=<service-name>
kubectl get pods -n traefik
kubectl logs -n traefik deploy/traefik --tail=100
kubectl get events -n <namespace> --sort-by=.lastTimestamp
```

Traefik 自带 Dashboard，Helm 安装默认启用但未对外暴露，排查路由问题时可以端口转发临时访问：

```bash
kubectl port-forward -n traefik deploy/traefik 9000:9000
```

浏览器打开 `http://127.0.0.1:9000/dashboard/`，结尾的斜杠不能省略。Dashboard 会列出所有 router、middleware 和 service 的生效状态与报错详情，Middleware 引用拼写错误、Secret 缺失这类问题在这里一目了然。Dashboard 本身没有认证，不应在生产环境直接暴露。

常见现象如下：

| 现象            | 可能原因                                        | 检查方向                                        |
|---------------|---------------------------------------------|---------------------------------------------|
| Ingress 无访问效果 | 没有安装控制器，或 `ingressClassName` 不匹配            | `kubectl get ingressclass`、控制器启动参数          |
| `ADDRESS` 为空  | 控制器未更新状态，或暴露方式不写回地址                         | 控制器 Service、`status.loadBalancer`、控制器日志     |
| 404           | Host 或 Path 不匹配，后端应用路径不存在，注解引用的 Middleware 不存在 | `rules.host`、`pathType`、Middleware 引用拼写、控制器日志 |
| 401           | Basic Auth、外部认证或应用认证拦截                      | 认证中间件、Secret 的 `users` 键、认证服务日志             |
| 403           | 来源不在 `ipAllowList` 允许范围                     | 允许名单、控制器看到的来源 IP                            |
| 413           | 请求体超过 `buffering` 限制                        | `maxRequestBodyBytes`                       |
| 429           | 触发 `rateLimit` 限流                           | `average`、`burst`、副本数放大效应                   |
| 502           | 后端协议不匹配，后端连接失败，TLS 后端配置错误                   | 后端协议配置、Pod 端口、应用日志                          |
| 503           | Service 不存在、端口错误、没有可用后端端点                   | Service、EndpointSlice                       |
| 504           | 后端处理超时或连接超时                                 | 入口点 `respondingTimeouts`、应用耗时               |
| HTTPS 证书异常    | Secret 不存在、证书链顺序错误、证书域名与 Host 不匹配           | TLS Secret、控制器日志、SNI Host                   |
| 黑白名单不生效       | 控制器看到的源 IP 不是客户端真实 IP                       | 前置 LB、PROXY protocol、`ipStrategy` 配置        |

Middleware 引用错误是 Traefik 下最常见的新手问题：注解里的引用必须是「Namespace + `-` + 名称 + `@kubernetescrd`」，任何一段拼写错误都会导致路由不生效，控制器日志中会出现 `middleware ... does not exist` 类的报错。

排查时不要只看 Ingress YAML。Ingress 是七层路由声明，真正决定访问结果的还包括控制器部署方式、边界负载均衡器、DNS、TLS Secret、Service selector、EndpointSlice、Pod readiness、NetworkPolicy 和应用自身路由。ingress-nginx 特有的排查要点见[附录：ingress-nginx](./appendix-ingress-nginx.md)。

## 配置建议

- 新 Ingress 明确设置 `spec.ingressClassName`
- 普通路径优先使用 `Prefix` 或 `Exact`，正则路径再使用 `ImplementationSpecific`
- Ingress 后端优先引用 Service 端口名，降低端口号变更影响
- TLS Secret、Ingress、Middleware 和后端 Service 放在同一 Namespace 中统一管理
- 控制器注解的值都按字符串写入，避免布尔值或数字被 YAML 解析成其他类型
- Middleware 与引用它的 Ingress 一起提交、一起回滚，避免出现悬空引用
- 认证中间件只作为轻量保护，不替代完整身份认证体系
- 限流、黑白名单依赖真实客户端 IP，应先确认前置负载均衡与转发头配置
- 复杂灰度、跨 Namespace 网关、多团队路由和多协议入口优先评估 Gateway API 或服务网格
- 控制器安装和升级以所选控制器官方文档为准，不直接复制旧版本清单
- 仍在使用 ingress-nginx 的集群应制定迁移计划，优先评估 Gateway API 或其他维护中的控制器

## 参考

本文内容参考 Traefik 官方文档以及相关 Kubernetes 文档：

- [Traefik Setup on Kubernetes](https://doc.traefik.io/traefik/setup/kubernetes/)
- [Traefik Kubernetes Ingress Routing](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/ingress/)
- [Traefik HTTP Middlewares](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/overview/)
- [Traefik BasicAuth](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/basicauth/)
- [Traefik ForwardAuth](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/forwardauth/)
- [Traefik RateLimit](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/ratelimit/)
- [Traefik InFlightReq](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/inflightreq/)
- [Traefik Headers](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/headers/)
- [Traefik Errors](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/errorpages/)
- [Traefik TraefikService](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/crd/http/traefikservice/)
- [Traefik API & Dashboard](https://doc.traefik.io/traefik/reference/install-configuration/api-dashboard/)
- [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Gateway API](https://kubernetes.io/docs/concepts/services-networking/gateway/)
