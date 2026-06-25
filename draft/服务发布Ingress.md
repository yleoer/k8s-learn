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





