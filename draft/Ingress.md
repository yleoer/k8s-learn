# Ingress

## 什么是 Ingress

Ingress 为 Kubernetes 集群中的服务提供了一个统一的入口，可以提供负载均衡/SSL 终止和基于名称（域名）的虚拟主机/应用的灰度发布等功能，在生产环境中常用的Ingress控制器有Treafik/Nginx/HAProxy/Istio等。

相对于 Service，Ingress工作在七层（部分Ingress控制器支持4和6层），所以可以支持HTTP协议的代理，也就是基于域名的匹配规则。

## Ingress 和 Ingress Controller

Ingress 相当于 nginx.conf

Ingress Controller 相当于 Nginx

## k8s使用域名发布服务的流程

浏览器访问 baidu.com -> DNS 解析 -> DMZ 入口网关/SLB -> Ingress Controller -> Service -> Pod

## Ingress Controller 生产级高可用架构

Internet -> DMZ/网关  F5/SLB/LVS/HAProxy -> Kubernetes HostNetwork

// 增加一个 istio 的文档

官方安装文档：https://kubernetes.github.io/ingress-nginx/deploy/#bare-metal-clusters

```yaml
# 更改部署类型
#kind: Deployment
kind: DaemonSet
# 添加 hostNetwork
spec:
  hostNetwork: true
# 更改 DNS  解析策略
#dnsPolicy: ClusterFirst
dnsPolicy: ClusterFistWithHostNet
# 选择专用节点
nodeSelector:
  kubernetes.io/os: linux
  ingress: "true"
```

```bash
# 修改节点标签，配置为 ingress 专用节点
kubectl label node work02 ingress=true

# 创建 Ingress
kubectl create -f ingress-nginx-daemonset.yaml

# netstat -ltunp | grep nginx
```

## Ingress 资源定义

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
spec:
  ingressClassName: nginx # 指定该 Ingress 被哪个 Controller 解析
  rules: # 定义路由匹配规则，可以配置多个
  - host: nginx.test.com # 定义域名
    http:
      paths: # 详细的路由配置，可以配置多个
      - backend: # 指定该路由的后端
          service:
            name: nginx
            port: 
              number: 80
        path: / # 指定 PATH
        pathType: ImplementationSpecific # 指定匹配规则
```

pathType: 路径的匹配方式：

- Exact: 精确匹配，比如配置的 path 为 /bar，那么 /bar/ 将不能被路由
- Prefix: 前缀匹配，基于以 / 分隔的 URL 路径，比如 path 为 /abc，可以匹配到 /abc/bbb等
- ImplementationSpecific: 这种类型的路由匹配根据 Ingress Controller 来实现，可以当做一个单独的类型，也可以当做 Prefix 和 Exact

```bash
# 查看 ingress controller name
kubectl get ingress
kubectl get ingressclass
```

## 使用域名发布 k8s 的服务

创建一个 web 服务

```bash
kubectl create deploy nginx --image=nginx:1.15.12
```

暴露服务

```bash
kubeclt expose deploy nginx --port 80
```

创建 Ingress
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
spec:
  ingressClassName: nginx
  rules:
  - host: nginx.test.com
    http:
      paths:
      - backend:
          service:
            name: nginx
            port: 
              number: 80
        path: /
        pathType: ImplementationSpecific
```

## 不配置域名发布服务

去掉 `host`即可

```yaml
spec:
  ingressClassName: nginx
  rules:
   - http:
       paths:
       - backend:
          service:
            name: nginx
            port:
              number: 80
        path: /no-host
        pathType: ImplementationSpecific
```

## Ingress 实战

### 配置练习环境

创建一个用于学习 Ingress 的 Namespace，之后所有的操作都在此 Namespace 进行

```bash
kubectl create ns study-ingress
```

创建一个 Nginx 模拟 Web 服务

```bash
kubectl create deploy nginx --image=nginx:1.15.12 -n study-ingress
```

创建 Service

```bash
kubectl expose deploy nginx --port 80 -n study-ingress
```

### 使用 HTTPS 发布服务

生产环境对外的服务，一般需要配置 https 协议，使用 Ingress 也可以非常方便的添加 https 的证书

由于是学习环境，没有权威的证书，所以使用 OpenSSL 生成一个测试证书。（通常情况下，证书放在网关）

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=nginx.text.com"
kubectl create secret tls ca-secret --cert=tls.crt --key=tls.key -n study-ingress
```

配置 Ingress 添加 TLS 配置

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
  namespace: study-ingress
spec:
  ingressClassName: nginx
  rules:
  - host: nginx.test.com
    http:
      paths:
      - backend:
          service:
            name: nginx
            port: 
              number: 80
        path: /
        pathType: ImplementationSpecific
  tls:
  - hosts:
    - nginx.test.com
      secretName: ca-secret
```

```bash
curl -I -k -L nginx.test.com
```

可以看到 Ingress 添加 TLS 配置也非常简单，只需要在 spec 下添加一个 tls 字段即可：

- hosts: 证书所授权的域名列表
- secretName: 证书的 Secret 名字
- ingressClassName: ingress class 的名字

### 域名添加用户名密码认证

有些开源工具本身不提供密码认证，如果暴露出去会有很大风险，对于这类工具可以使用 Nginx 的 basic-auth 设置密码访问，具体方法如下，由于需要使用 htpasswd 工具，所以需要安装 httpd：

```
apt install -y httpd
```

使用 htpasswd 创建 foo 用户的密码

```bash
htpassed -c auth foo
```

基于之前创建的密码文件创建 Secret

```bash
kubectl create secret generic basic-auth --from-file=auth -n study-ingress
```

创建包含密码认证的 Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    nginx.ingress.kubernetes.io/auth-realm: Please Input Your Username and Password
    nginx.ingress.kubernetes.io/auth-secret: basic-auth
    nginx.ingress.kubernetes.io/auth-type: basic
```

### 开启会话保持

和 Nginx 一样，Ingress Nginx 也支持基于 cookie 的会话保持。

首先扩容 nginx 服务至多个副本

```bash
kubectl scale deploy nginx --replicas=3 -n study-ingress
```

未开启会话保持，同一个主机访问可以看到流量在三个副本中都有。

通过配置，即可看到流量只会进入到一个 Pod

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
  namespace: study-ingress
  annotations:
    nginx.ingress.kubernets.io/proxy-body-size: 16m
    nginx.ingress.kubernets.io/affinity: "cookie"
    nginx.ingress.kubernets.io/session-cookie-name: "route"
    nginx.ingress.kubernets.io/session-cookie-expires: "172800"
    nginx.ingress.kubernets.io/session-cookie-max-age: "172800"
    # 后端负载扩容后，是否需要重新分配流量，balanced: 重新分配，persistent: 保持
    nginx.ingress.kubernets.io/affinity-mode: persistent
```

### 配置流式返回 SSE

如果后端服务需要持续的输出数据，或者需要长链接，此时需要更改请求头升级链接为长链接

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
  namespace: study-ingress
  annotations:
    nginx.ingress.kubernets.io/proxy-http-version: "1.1"
    nginx.ingress.kubernets.io/proxy-buffering: "off"
    # snippet 通常用于配置一些不支持或者复杂的参数，比如配置请求头，或者逻辑控制
    nginx.ingress.kubernets.io/configuration-snippet: |
      proxy_set_header Updrade $http_updrade;
      proxy_set_header Connection 'upgrade';
```

### 域名重定向 Redirect

在使用 Nginx 作为代理服务器时，Redirect 可用于域名的重定向，比如访问 old.com 被重定向到 new.com。Ingress 也可以实现 Redirect 功能。

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
  namespace: study-ingress
  annotations:
    nginx.ingress.kubernets.io/permanent-redirect: https://www.baidu.com
    nginx.ingress.kubernets.io/permanent-redirect-code: "308"
```

### 访问地址重写 Rewrite

web: /

backend-a: /api

backend-b: /api

重写 /api-a -> /api /api-b -> /api

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
  namespace: study-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: $2
spec:
  ingressClassName: nginx
  rules:
  - host: nginx.test.com
    http:
      paths:
      - backend:
          service:
            name: nginx
            port: 
              number: 80
        path: /api-a(/|$).(.*)
        pathType: ImplementationSpecific
```

/api-a/test/test -> /test/test

需要重写的和不需要重新的不要放在一起