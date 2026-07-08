# 附录：ingress-nginx 存量注解参考

ingress-nginx（`kubernetes/ingress-nginx`）已于 2026 年 3 月正式退役。本附录保留其安装形态、注解扩展和排查要点，仅作为存量集群的维护参考；Ingress API 本身的字段与规则见 [Ingress](./5-Ingress.md)，退役时间线、控制器选型和迁移路径见 [Ingress 控制器选型与 Gateway API 迁移](./6-Ingress控制器选型与GatewayAPI迁移.md)。

> [!WARNING]
> ingress-nginx 仓库已归档只读，不再发布新版本，也不再修复缺陷和安全漏洞，此后发现的 CVE 会持续累积。以下内容不应再用于新集群设计，存量集群应按安全风险排期迁移。

## 安装形态

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

## TLS 重定向行为

ingress-nginx 中，配置了 TLS 块时默认会把 HTTP 重定向到 HTTPS，默认重定向状态码为 308。是否启用重定向、是否使用默认证书、是否启用 SSL Passthrough 都属于 ingress-nginx 控制器配置范围，不是 Ingress API 的通用字段。

## 注解扩展

以下内容只适用于 ingress-nginx。其他 Ingress Controller 可能使用完全不同的注解、CRD 或配置入口。

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

更复杂的 NGINX 片段可以通过 `configuration-snippet` 插入到 location 配置中，但这类能力风险较高，是否允许通常由集群管理员控制。多租户集群中不应默认开放任意 snippet 注解。`configuration-snippet` 在 Gateway API 中没有等价物，是迁移时需要人工重新设计的典型项。

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

Canary 条件有优先级：header 高于 cookie，cookie 高于权重。ingress-nginx 对同一 Ingress 规则最多应用一个 Canary Ingress。更复杂的蓝绿、灰度、流量镜像和基于请求属性的路由，更适合 Gateway API、服务网格或专门的发布系统。

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

## 排查要点

ingress-nginx 部署下的常用排查命令：

```bash
kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=100
```

ingress-nginx 特有的常见现象：

| 现象         | 可能原因                        | 检查方向                                                        |
|------------|-----------------------------|-------------------------------------------------------------|
| 413        | 请求体超过默认 1m 限制               | `nginx.ingress.kubernetes.io/proxy-body-size` 或全局 ConfigMap |
| 502        | 后端协议不匹配                     | `nginx.ingress.kubernetes.io/backend-protocol`、Pod 端口       |
| 503        | Basic Auth Secret 的键不是 `auth` | Secret 键名                                                   |
| 504        | 代理超时                        | `proxy-read-timeout`、`proxy-send-timeout` 注解                |
| HTTP 被 308 重定向 | TLS 块触发默认强制跳转           | `ssl-redirect` 相关配置                                         |

## 参考

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
