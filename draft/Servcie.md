# 服务发布

在 k8s 上是如何发布服务的

服务发布分类：

- 用户访问 - Ingress
- 服务间访问 - Service
- 基础组件访问

// k8s 集群服务发布架构图-无注册中心

// k8s 集群服务发布架构图-有注册中心

## 东西流量管理：Service

### Label & Selector

Label：k8s 任何资源都有标签的概念，用于给同类的资源进行分组。比如一个集群有很多个节点，可以根据不同的地域/网段/节点类型进行分组，方便管理。

Selector：标签选择器可以通过同一类资源的不同标签进行精确的查询数据。比如想要查询某个命名空间下所有具有app=payment标签的Pod，可以使用Selector进行过滤。

### Service 匹配 Pod

```yaml
apiVersion: v1
kind: Service
metadata:
  name: payment
spec:
  selector:
    app: payment
    role: api
  ports:
    - protocol: TCP
      port: 80         # Service 自己的端口号，请求的端口号
      targetPort: 8080 # 目标端口号
```

当 selector 有多个规则，需要完全匹配才行，比如下面两个，Service 只会匹配到 PodA

```text
PodA:
  label:
    app: payment
    role: api

PodB:
  label:
    app: payment
    role: cron
```

加标签

```bash
kubectl label 资源类型 [资源名称] key=value

# 给指定的 deploy 添加标签
kubectl label deploy nginx-deploy version=v1

# 显示 deploy 的标签
kubectl get deploy --show-labels

# 给所有 deploy 添加标签
kubectl label deploy --all svc=true

I# 给过滤的 deploy 添加标签
kubectl get deploy -l app # 只过滤存在 key 的 deploy
kubectl label deploy -l app=nginx svc2=true

# 同时添加多个标签
kubectl label deploy nginx a=b c=d
```

修改标签

已经存在的标签，不允许直接修改，需要加 `--overwrite` 参数才能修改

```bash
kubectl label deploy nginx-deploy svc=false --overwrite
```

删除标签

```bash
kubectl label deploy nginx-deploy svc-
```

使用 `--show-labels` 查看所有标签

```bash
kubectl get deploy --show-labels

# 查询 app 为 nginx 的 deploy
kubectl get deploy -l app=nginx

# 查询 app 为 nginx 或 backend 的 deploy
kubectl get deploy -l 'app in (nginx, backend)' --show-labels

# 查询 app 为 nginx 或 backend 但不包含 version=v1 的 deploy
kubectl get deploy -l 'app in (nginx, backend)' -l version!=v1 --show-labels

# 查询 label 的 key 为 app 的 deploy
kubectl get deploy -l app --show-labels

# 查询所有命名空间的资源
kubectl get deploy -l app=nginx -A
```

使用案例

公司与银行有一条专属的高速光纤通道，此通道只能与 192.168.7.0 网段进行通信，因此只能将与银行通信的应用部署到 192.168.7.0 网段所在的节点上，此时可以对节点添加 label：

```bash
kubectl label node work02 region=subnet7
```

然后可以通过 Selector 对其筛选：

```bash
kubectl get no -l region=subnet7
```

在 Pod template 添加：

```yaml
spec:
  nodeSelector:
    region: subnet7
```

结果所有 pod 都到了 work02 节点上：

```bash
$ kubectl get po -owide           
NAME                            READY   STATUS      RESTARTS   AGE   IP               NODE     NOMINATED NODE   READINESS GATES
nginx-deploy-55999d5cd8-69tq4   1/1     Running     0          3s    10.244.75.118    work02   <none>           <none>
nginx-deploy-55999d5cd8-gw229   1/1     Running     0          2s    10.244.75.119    work02   <none>           <none>
nginx-deploy-55999d5cd8-kkh8f   1/1     Running     0          1s    10.244.75.120    work02   <none>           <none>
nginx-deploy-698d79587c-lkz2g   0/1     Completed   0          16m   10.244.205.236   work01   <none>           <none>

$ kubectl get po -owide
NAME                            READY   STATUS    RESTARTS   AGE   IP              NODE     NOMINATED NODE   READINESS GATES
nginx-deploy-55999d5cd8-69tq4   1/1     Running   0          7s    10.244.75.118   work02   <none>           <none>
nginx-deploy-55999d5cd8-gw229   1/1     Running   0          6s    10.244.75.119   work02   <none>           <none>
nginx-deploy-55999d5cd8-kkh8f   1/1     Running   0          5s    10.244.75.120   work02   <none>           <none>
```

### 什么是 Service

Service 是 k8s 开箱即用的一个用于提供负载均衡/服务发现等能力的资源。

Service 为 Pod 提供了一个抽象层，将一组具有相同功能的 Pod 抽象为一个逻辑上的服务。无论匹配的 Pod 如何变化，比如重启/迁移/扩缩容等，Service 都能保持一个稳定的访问接口，从而让我们无需关系服务所在的具体位置/IP等细节。

主要功能：

- 服务之间的服务发现
- 代理一个或一组Pod
- 代理IP或域名

### 什么是 Endpoints

Endpoints 可以理解为 Service 的一部分，主要用于记录 Service 对应的所有 Pod 的 IP 地址和端口信息。Service 通过 Endpoints 来找到并访问后端的 Pod。

Endpoints 资源记录了 Pod 的 IP 地址和端口列表，当后端 Pod 产生变化时，k8s 的控制器会更新 Endpoints 里面的配置信息，从而保证 Service 能够正确的路由到关联且正常运行的 Pod。

只有当 Service 名称和端口信息与 Endpoints 一样时，Service 和 Endpoints 才会自动建立关联。



### Service 资源定义

```yaml
apiVersion: v1
kind: Service
spec:
  ports:
  - name: dns # Service 端口名字
    port: 53 # Service 端口
    protocol: UDP # 代理协议
    targetPort: 53 # 目标端口，程序端口
  - name: dns-tcp
    port: 53
    protocol: TCP
    targetPort: 53
  selector: # 代理到哪些 Pod
    k8s-app: kube-dns
  sessionAffinity: None # 会话保持配置
  type: ClusterIP # Service 类型
```

Service 支持将一个接收端口映射到任意的 targetPort，如果 targetPort 为空，将被设置为与 Port 字段相同的值。targetPort 可以设置为一个字符串，引用 Pod 的一个端口的名称，这样的话即使更改了 Pod 的端口，也不会对 Service 的访问造成影响。

Kubernetes Service 能够支持TCP、UDP、SCTP等协议，默认为TCP协议

### Service 类型

- ClusterIP：在集群内部使用，默认值，只能从集群中访问
- NodePort：在所有安装了 Kube-Proxy 的节点上打开一个端口，此端口可以反代至后端 Pod，可以通过 NodePort 从集群外部访问集群内的服务，格式为 NodeIP:NodePort
- ExternalName：通过返回定义的 CNAME 别名，没有设置任何类型的代理，需要 1.7 更高版本 kube-dns 支持
- LoadBalancer：使用云提供商的负载均衡器公开服务，成本较高

### 定义 Service

创建 Service 可以使用 expose 命令和通过 yaml 文件定义。通过 expose:

```bash
kubectl expose deploy nginx --port 80
```

通过 yaml 文件定义 Service：

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  selector:
    app: nginx
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
```

// 通过另外的 cluster-test pod 进行测试

```bash
kubectl exec -it cluster-test-xxx -- bash
nslookup nginx
curl nginx
```

### NodePort 类型

如果将 Service 的 type 字段设置为 NodePort，则 Kubernetes 将从 --service-node-port--range 参数指定的范围（默认为 30000--32767）中自动分配端口，也可以手动指定 NodePort，创建该 Service 后，集群每个节点都将暴露一个端口，通过某个宿主机的 IP+端口即可访问到后端的应用。

// 为什么默认是 30000-32767

```yaml
spec:
  type: NodePort
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
    nodePort: 30001 # 自定义
```

// 示例

//  如何修改 --service-node-port-range 参数的默认值

### ExternalName Service

ExternalName Service 是 Service 的特例，它没有 Selector，也没有定义任何端口和Endpoint，它通过返回该外部服务的别名来提供服务，和域名解析的 CNAME 类似。

比如可以定义一个 Service，后端设置为一个外部域名，这样通过 Service 的名称即可访问到。

//应用场景 不同环境：测试，开发等，可以使用同一个 name 去连接 redis

//示例

### 使用 Service 代理 k8s 外部服务

使用场景：

- 希望在生产环境中使用某个固定的名称而非 IP 地址访问外部的中间件服务
- 希望 Service 指向另一个 Namespace 中或其他集群中的服务
- 正在将工作负载转移到 Kubernetes 集群，但是一部分服务仍运行在 Kubernetes 集群之外的 backend

```yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    app: nginx-svc-external
  name: nginx-svc-external
spec:
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 80
  sessionAffinity: None
  type: ClusterIP
---
apiVersion: v1
kind: Endpoints
metadata:
  labels:
    app: baidu-external
  name: baidu-external
subsets:
- addresses:
  - ip: 110.242.68.3 # baidu.com ip 地址
  ports:
  - name: http
    port: 80
    protocol: TCP
```

### 多端口 Service

有的程序可能会监听多个端口，Service 也支持同时代理多个端口。比如在 k8s 中部署一个 RabbitMQ，它具有两个端口，5672是程序连接用于数据交互的接口，15672是RabbitMQ管理页面的端口。

首先在 k8s 上部署一个RabbitMQ：

```bash
kubectl create deploy rabbitmq --image=rabbitmq:3-management
```

接下来可以创建一个 Service，把 5672 指向 Pod 的 5672，15672指向 15672:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: rabbitmq
spec:
  selector:
    app: rabbitmq
  ports:
  - name: amqp
    protocol: TCP
    port: 5672
    targetPort: 5672
  - name: http-web
    protocol: TCP
    port: 15672
    targetPort: 15672
```

### 会话保持

流量走同一个 pod，而不是轮询 pod

// 会话保持的概念

k8s 的 Service 支持会话保持，但是目前仅支持基于客户端IP的会话保持：

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
spec:
  selector:
    app: nginx
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  sessionAffinity: ClientIP # 基于 IP 的会话保持，None：不开启会话保持
  sessionAffinityConfig: # 会话保持配置
    clientIP:
      timeoutSeconds: 10800
```

### Headless Service

Headless Service 是 Kubernetes 中一种特殊类型的 Service，它直接暴露 Pod 的 IP 地址和 DNS 记录给客户端，适用于有状态应用的服务发现和负载均衡以及需要直接访问 Pod IP 的应用场景。

Headless Service 不需要分配 ClusterIP，而是通过 DNS 记录直接返回 Pod 的 IP 地址，所以和普通 Service 最大的区别就是使用 nslookup 解析一个 Headless Service 返回的是 Pod IP，而普通 Service 返回的是 Service 的 IP。

使用场景：

- 有状态应用的服务发现和负载均衡：有状态应用（如数据库、消息队列）通常需要为每个Pod分配一个唯一的标识符，以便其他服务或其他节点可以连接到某个实例。Headless Service 可以满足这一需求，通过直接暴露 Pod 的 IP 地址和 DNS 记录，实现服务发现和负载均衡。
- 需要直接访问 Pod IP 的应用：在某些情况下，客户端可能需要直接访问 Pod 的 IP 地址，而不需要通过 Service 的负载均衡机制，此时也可以通过 Headless Service 实现。
- 分布式系统：在分布式系统中，每个节点之间需要直接通信，并且每个节点都有自己的身份和状态。Headless Service 可以为每个节点分配一个唯一的 DNS 实体名称，支持节点之间的直接交互和负载均衡。

### Service 代理模式

#### iptables 模式

iptables 是 Linux 原生提供的一个功能强大的防火墙工具，可以用来设置、维护和检查 IPv4数据包，并且支持源目地址转换等规则。在 iptables 代理模式下，kube-proxy 通过监听 kubernetes API Server 中 Service 和 Endpoint 对象的变化，动态的更新节点上的 iptables 规则，以实现请求的转发。

工作流程：

1. 当 Service 被创建或更新时，kube-proxy 会读取 Service 和 Endpoint 对象的信息，并生成相应的 iptables 规则
2. 这些 iptables 规则被添加到内核的 netfilter 处理链中，以拦截和转发目标为 Service IP 地址的流量
3. 当客户端访问 Service 的 IP 地址时，iptables 规则会将流量随机重定向到后端的一个或多个 Pod

优缺点：

- 优点：iptables 是 Linux 内核的一部分，性能稳定、可靠，iptables 规则易于理解和维护，功能多。
- 缺点：随着 Service 数量的增加，iptables 规则的数量也会急剧增加，进而导致性能下降，iptables的更新操作可能会暂时锁定整个 iptables 规则表，影响网络性能。

#### IPVS 代理模式

IPVS（IP Virtual Server）是一种基于内核的负载均衡器，提供了比 iptables 更高的转发性能。在 IPVS 代理模式下，kube-proxy 通过配置 IPVS 负载均衡器规则来代替使用 iptables。IPVS 使用更高效的数据结构（如 Hash 表）来存储和查找规则，可以在大量Service的情况下也能保持高性能。

工作流程：

1. 当 Service 被创建或更新时，kube-proxy 会读取 Service 和 Endpoint 对象的信息，并配置 IPVS 负载均衡策略
2. IPVS 负载均衡器会更具配置的调度算法（如轮询、最少连接等）将请求转发到后端的一个或多个 Pod上
3. 当客户端访问 Service 的 IP 地址时，请求会直接被 IPVS 处理并转发到后端 Pod。

优缺点：

- 优点：IPVS 专为负载均衡设计，性能优于 iptables。并且支持多种调度算法，可以根据实际需求选择合适的算法，同时 IPVS 的更新操作对性能的影响较小
- 缺点：在某些情况下，IVPS 可能需要依赖 iptables 来实现一些额外的功能（如源地址NAT）

IPVS  负载均衡算法：

- 轮询：rr，按顺序轮流将请求转发到后端的各个 Pod 上，实现请求的均匀分配
- 最少连接：lc，将新的请求转发到当前连接数最少的Pod上，以平衡各Pod的负载
- 源地址哈希：sh，根据请求的源IP地址进行哈希计算，将相同源地址的请求转发到同一个 Pod 上，实现会话保持
- 目的地址哈希：dh，根据请求的目的IP地址（即Service的Cluster IP）和端口进行哈希计算，选择后端Pod
- 无需队列等待：nq，如果后端Pod的队列为空，则直接选择该Pod；如果所有Pod的队列都非空，则采用其他策略来选择Pod
- 最短期望延迟：sed，考虑Pod的当前连接数和连接请求的平均处理时间，选择预计处理时间最短的Pod

### 更改 Service 代理模式

查看当前的代理模式

```bash
curl 127.0.0.1:10249/proxyMode
```

更改代理模式为 ipvs：

```bash
kubectl edit cm kube-proxy -n kube-system
# mode: "ipvs"
```

重启 kube-proxy 生效

```bash
kubectl patch daemonset kube-proxy -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"date\":\"`date+'%s'`\"}}}}}" -n kube-system
```

更改 IPVS 算法：

```bash
kubectl edit cm kube-proxy -n kube-system
# ipvs:
#   scheduler: "lc"
```

