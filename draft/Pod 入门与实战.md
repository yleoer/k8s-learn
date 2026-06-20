# Pod 入门与实战

## Pod 配置字段详解

### 创建一个 pod

定义一个pod

```yaml
apiVersion: v1 # 必选，API的版本号，通过 kubectl api-resources 确定
kind: Pod # 必选，类型 Pod
metadata: # 必选，元数据
  name: nginx # 必选，符合 RFC 1035 规范的 Pod 名称
spec: # 必选，用于定义 Pod 的详细信息
  containers: # 必选，容器列表
  - name: nginx # 必选，符合 RFC 1035 规范的容器名称
    image: registry.cn-beijing.aliyuncs.com/dotbalo/nginx:stable # 必选，容器所用的镜像
    ports: # 可选，容器需要暴露的端口号列表
      - containerPort: 80 # 端口号
```

创建 Pod

```bash
kubectl create -f nginx.yaml
```

查看 Pod 状态

```bash
kubectl get po nginx
```

使用 kubectl run 创建一个 Pod

```bash
kubectl run nginx-run ---image=nginx:1.15.12
```



### 一个 Pod 多个容器

定义一个 Pod 多个容器

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  containers:
  - name: nginx
    image: registry.cn-beijing.aliyuncs.com/dotbalo/nginx:stable
    ports:
    - containerPort: 80
  - name: redis # 多个容器不能重名
    image: registry.cn-beijing.aliyuncs.com/dotbalo/redis:7.2.5
    ports:
    - containerPort: 6379
```

### 更改 Pod 的启动命令和参数

```bash
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spce:
  containers:
  - name: nginx
    image: nginx:stable
    command:
    - sleep
    - "600"
```

### 分配 CPU 和内存

为容器分配CPU和内存

```yaml
spec:
  containers:
  - name: nginx
    image: nginx: stable
    resources:
      requests: # 直接分配，会影响到节点对pod的分配“明明有资源，却不分配”
        memory: "100Mi"
        cpu: 100m # 1 核等于 1000m
      limits: # 最多能达到多少
        memory: "200Mi"
        cpu: 200m
```

```bash
kubectl describe no work01
```

- Capacity: 节点容量
- Allocatable: 可分配资源
- Non-terminated Pods
- 并没有根据实际使用量去分配pd

### Pod 键值对和 fieldRef 环境变量配置

```yaml
spec:
  containers:
  - name: env-test
    image: nginx:stable
    env:
    - name: ENV
      value: test
    - name: POD_NAME
      valueFrom:
        fieldRef:
          fieldPath: metadata.name
    - name: POD_NAMESPACE
      valueFrom:
        fieldRef:
          fieldPath: metadata.namespace
    - name: POD_NODE_NAME
      valueFrom:
        fieldRef:
          fieldPath: spec.nodeName
    - name: POD_IP
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
```

//TODO 常用的内置字段

### Pod 镜像拉取策略

通过 spec.containers[].imagePullPolicy 参数可以指定镜像的拉取策略，目前支持的策略如下：

- Always: 总是拉取，当镜像tag为latest时，且imagePullPolicy未配置，默认为Always
- Never：不管是否存在都不会拉取
- IfNotPresent：镜像不存在时拉取镜像，如果tag为非latest，且imagePullPolicy未配置，默认为IfNotPresent

```yaml
spec:
  containers:
  - name: nginx
    image: nginx:stable
    imagePullPolicy: IfNotPresent
```

明明有镜像，为什么还要下载镜像，为什么还下载失败了？

- Runtime 错了，每个节点都要导入
- ctr 需要使用 -n k8s.io
- imagePullPolicy 配置成了 Always

### Pod重启策略

通过 spec.restartPolicy 指定容器的重启策略

- Always：默认策略，容器失效时，自动重启该容器
- OnFailure：容器以不为0的状态码终止，自动重启该容器
- Never：无论何种状态，都不会重启

### Pod的三种探针

Pod生命周期-启动过程：

创建Pod，Pending，ContainerCreating，Running，InitContainer，Container，StartupProbe，LivenessProb/ReadinessProbe，Endpoint添加Pod IP

Pod生命周期-退出过程：

删除Pod，Dead（宽限期内30s），Terminating，PreStop（宽限期结束PreStop未结束，再次获得2s的宽限期），Endpoints删除Pod IP，宽限期结束，Pod收到SIGKILL信号，kubectl请求APIServer，将宽限期设置为0，然后进行删除操作

//TODO，整理两个过程，每个阶段的含义，操作

- startupProbe：用于判断容器内的应用程序是否已经启动。如果配置了startupProbe，就会先禁用其他探测，直到它成功为止。如果探测失败，kubelet会杀死容器，之后根据重启策略进行处理，如果探测成功，或没有配置startupProbe，则状态为成功，之后就不再探测
- livenessProbe：用于探测容器是否在运行，如果探测失败，kubelet会杀死容器并根据重启策略进行相应的处理。如果未指定该探针，将默认为Success
- redinessProbe：一般用于探测容器内的程序是否健康，即判断容器是否为就绪（Ready）状态。如果是，则可以处理请求，反之Endpoints Controller 将从所有的 Service 的 Endpoints 中删除此容器 Pod 的 IP 地址。如果未指定，将默认为 Success。

### 探针的四种检查方式

- ExecAction：在容器内执行一个指定的命令，如果命令返回值为0，则认为容器健康
- TCPSocketAction：通过TCP连接检查容器指定的端口，如果端口开放，则认为容器健康
- HTTPGetAction：对指定的URL进行Get请求，如果状态码在200~400之间，则认为容器健康
- GRPC：GRPC协议的健康检查，如果响应的状态是“SERVING”，则认为容器健康

### livenessProbe和readinessProbe

//示例演示

```yaml
readinessProbe:
  httpGet:
    path: /index.html
    port: 80
    scheme: HTTP # HTTP or HTTPS
  initialDelaySeconds: 10 # 初始化时间，健康检查延迟执行时间
  timeoutSeconds: 2 # 超时时间
  periodSeconds: 5 # 检测间隔
  successThreshold: 1 # 检查成功 1 次此表示就绪
  failureThreshold: 2 # 检查失败 2 次表示未就绪
  tcpSocket:
    port: 80
```



### 配置 StartupProbe

//示例演示

### preStop和postStart

//示例演示

postStart 并不能保证在 command 之前执行，异步同时执行

```yaml
lifecycle:
  postStart: # 容器创建完成后执行的指令，可以是 exec httpGet TCPSocket sleep
    exec:
      command:
      - sh
      - -c
      - 'mkdir /data/'
  preStop:
    exec:
      command:
      - sh
      - -c
      - sleep 10
```

宽限期处理，修改配置：terminationGracePeriodSeconds

### gRPC探测

//示例演示

## 零宕机发版

