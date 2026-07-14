# 附录：ingress-nginx

ingress-nginx（`kubernetes/ingress-nginx`）已于 2026 年 3 月正式退役。本附录保留其退役背景、替代控制器选型、安装形态、存量注解和排查要点，仅作为存量集群的维护参考；Ingress API 本身的字段与规则见 [Ingress](./5-Ingress.md)，Gateway API 迁移记录见 [Gateway API](./6-GatewayAPI.md)。

> [!WARNING]
> ingress-nginx 仓库已归档只读，不再发布新版本，也不再修复缺陷和安全漏洞，此后发现的 CVE 会持续累积。以下内容不应再用于新集群设计，存量集群应按安全风险排期迁移。

## 退役时间线

本附录中的 ingress-nginx 指 Kubernetes 社区维护的 `kubernetes/ingress-nginx` 项目，常见 IngressClass 名称为 `nginx`，控制器标识为 `k8s.io/ingress-nginx`。

关键节点如下：

| 时间       | 事件                                                     |
|----------|--------------------------------------------------------|
| 2025-11-11 | Kubernetes 官方博客发布退役公告，宣布 best-effort 维护持续到 2026 年 3 月 |
| 2026-01-29 | Steering Committee 与 Security Response Committee 发布联合声明，要求使用者立即规划迁移 |
| 2026-03-19 | 发布 controller v1.15.1 与 Helm chart 4.15.1             |
| 2026-03-24 | GitHub 仓库归档为只读，项目退役                                  |

退役后的实际含义：

- 不再发布新版本，不再修复缺陷，也不再修复新发现的安全漏洞。
- 已有部署不会立即失效，已发布的 Helm chart 和容器镜像仍可下载。
- 存量部署继续运行会承担不断累积的安全风险，迁移窗口应按风险排期。
- 曾计划作为继任者的 InGate 项目未发展到可用程度，已一并退役。

确认集群中是否运行 ingress-nginx：

```bash
kubectl get po --all-namespaces --selector app.kubernetes.io/name=ingress-nginx
```

> [!WARNING]
> Ingress NGINX 与 NGINX Ingress Controller 是两个不同项目：退役的是 Kubernetes 社区的 `kubernetes/ingress-nginx`；F5 维护的 NGINX Ingress Controller（`nginx/kubernetes-ingress`）不受本次退役影响。二者都使用 NGINX 作为数据面，但注解体系和配置方式互不兼容，不能直接混用文档。

## 替代控制器选型

控制器退役不等于 Ingress API 被移除。Ingress API 仍是 GA API，官方没有移除计划；但 Ingress API 已冻结，不再扩展新能力。新入口设计应优先评估 Gateway API，存量 Ingress 资源如果暂时不改写，则需要替换为仍在维护的 Ingress Controller。

Kubernetes 官方 Ingress Controllers 列表中，由 Kubernetes 项目自身支持和维护的是 AWS 与 GCE Ingress Controller；其余常见控制器属于第三方项目。常见选项如下：

| 控制器                          | 数据面             | 记录要点                                      |
|------------------------------|-----------------|-------------------------------------------|
| Traefik                      | Traefik         | 同时支持 Ingress 与 Gateway API，动态配置能力较强       |
| HAProxy Ingress              | HAProxy         | 同时支持 Ingress 与 Gateway API                |
| NGINX Ingress Controller（F5） | NGINX           | 数据面同为 NGINX，但注解不兼容 ingress-nginx，迁移仍需逐条改写 |
| Cilium                       | eBPF + Envoy    | CNI 与入口能力结合较紧密，适合已经采用 Cilium 的集群         |
| Istio Ingress Gateway        | Envoy           | 适合已经使用 Istio 服务网格或 Envoy 体系的集群           |
| Kong、APISIX                  | OpenResty/NGINX | 偏 API 网关场景，通常提供认证、限流等插件体系               |
| 云厂商控制器                       | 云负载均衡           | AWS ALB、GCE、AKS Application Gateway 等托管环境优先评估 |

没有任何控制器能直接平替 ingress-nginx。选型时重点核对：

- 注解兼容性：`nginx.ingress.kubernetes.io/*` 注解不可平移，rewrite、正则路径、金丝雀、限流等能力需要在目标控制器中重新表达。
- Gateway API 支持状态：选择同时支持 Ingress 与 Gateway API 的控制器，可以把控制器替换和 API 迁移放在同一条演进路径上。
- 数据面运维经验：团队对 NGINX、HAProxy、Envoy 或云负载均衡的排障熟悉度会直接影响故障恢复速度。
- 行为差异验证：路径匹配、默认后端、转发头、超时、重定向和真实客户端 IP 识别等默认行为在各控制器之间可能不同。
- 一致性与生态：迁移到 Gateway API 时，应查看目标实现的 Gateway API conformance 状态，并确认所需功能是否属于标准字段、实验字段或实现私有扩展。

`ingress2gateway` 可以把 Ingress 及部分控制器私有注解转换为 Gateway API 资源，是迁移分析和初稿生成工具，不是一键替换工具。转换结果需要逐条审查，并在测试环境验证路由、TLS、重写、限流、灰度、默认后端和错误页行为后再切换流量。

## 安装形态

ingress-nginx 常见安装方式包括 Helm、官方静态清单、云厂商 LoadBalancer、裸金属 NodePort、`hostPort` 或 `hostNetwork`。裸金属环境如果希望直接使用节点的 80、443 端口，常见做法是选择专用节点运行 Ingress Controller，并把外部四层负载均衡器指向这些节点。

下面片段只用于说明 `hostNetwork` 方式涉及的字段关系，不是完整 ingress-nginx 安装清单：

```yaml{9-13}
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
kubectl label no <node-name> ingress=true
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

```yaml{6-9}
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

```yaml{6-11}
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

```yaml{6-8,14-16}
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

```yaml{6-8}
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

```yaml{6-9}
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

```yaml{6-10}
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

```yaml{6-10}
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

```yaml{25-27}
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

```yaml{6-8}
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
kubectl get po -n ingress-nginx -l app.kubernetes.io/component=controller
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

- [Ingress NGINX Retirement: What You Need to Know](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/)
- [Ingress NGINX: Statement from the Kubernetes Steering and Security Response Committees](https://kubernetes.io/blog/2026/01/29/ingress-nginx-statement/)
- [Ingress Controllers](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/)
- [A Welcome Guide for Ingress-NGINX Users](https://gateway-api.sigs.k8s.io/guides/getting-started/migrating-from-ingress-nginx/)
- [Announcing Ingress2Gateway 1.0](https://kubernetes.io/blog/2026/03/20/ingress2gateway-1-0-release/)
- [ingress2gateway](https://github.com/kubernetes-sigs/ingress2gateway)
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
