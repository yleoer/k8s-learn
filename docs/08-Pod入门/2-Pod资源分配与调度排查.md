# Pod 资源分配与调度排查

Kubernetes 使用 `resources.requests` 和 `resources.limits` 描述容器资源需求。调度阶段主要依据 requests 判断节点是否可放置，运行阶段由 kubelet、容器运行时和内核共同执行 limits 约束。

## requests 与 limits

| 字段         | 作用            | 主要影响                 |
|------------|---------------|----------------------|
| `requests` | 声明容器运行所需的资源基准 | Scheduler 根据它选择节点    |
| `limits`   | 限制容器最多可使用的资源  | kubelet、运行时和内核共同限制容器 |

下面示例为 `nginx` 容器同时配置 CPU 和内存的 requests、limits：

```yaml [resource-demo.yaml]
apiVersion: v1
kind: Pod
metadata:
  name: resource-demo
spec:
  containers:
    - name: nginx
      image: nginx:1.31-alpine
      resources:
        requests:
          cpu: 100m
          memory: 64Mi
        limits:
          cpu: 500m
          memory: 128Mi
```

该配置的含义如下：

| 配置项                         | 示例值     | 含义                 |
|-----------------------------|---------|--------------------|
| `resources.requests.cpu`    | `100m`  | 调度时为容器预留 0.1 核 CPU |
| `resources.requests.memory` | `64Mi`  | 调度时为容器预留 64Mi 内存   |
| `resources.limits.cpu`      | `500m`  | 容器最多使用 0.5 核 CPU   |
| `resources.limits.memory`   | `128Mi` | 容器最多使用 128Mi 内存    |

创建并查看 Pod：

```bash
kubectl create -f resource-demo.yaml
kubectl get pod resource-demo -o wide
kubectl describe pod resource-demo
```

::: details 输出示例

```bash
$ kubectl get po resource-demo -owide
NAME            READY   STATUS    RESTARTS   AGE   IP               NODE     NOMINATED NODE   READINESS GATES
resource-demo   1/1     Running   0          63m   10.244.205.199   work01   <none>           <none>

$ kubectl describe po resource-demo
Containers:
  nginx:
    Container ID:   containerd://60b0090037c415f603789e0eb210dd55c32cf77e4fbc8ae0f0c32ee6f31d2491
    Image:          nginx:1.31-alpine
    Image ID:       docker.io/library/nginx@sha256:92cf5e2f488744c90d3df4378dfa3f0842704950cfa1353975d5510c945b072f
    Port:           <none>
    Host Port:      <none>
    State:          Running
      Started:      Mon, 22 Jun 2026 10:10:52 +0800
    Ready:          True
    Restart Count:  0
    Limits:
      cpu:     500m
      memory:  128Mi
    Requests:
      cpu:        100m
      memory:     64Mi
    Environment:  <none>
    Mounts:
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-bgtdg (ro)
```

:::

在 `kubectl describe pod resource-demo` 的输出中，可以在 `Containers` 区域看到 `Requests` 和 `Limits`。其中 requests 会参与调度决策，并作为资源预留基准；limits 会在容器运行阶段形成资源上限。

CPU 使用毫核表示时，`100m` 表示 0.1 核，`500m` 表示 0.5 核，`1000m` 等于 1 核。内存常用 `Mi`、`Gi` 表示，例如 `64Mi`、`128Mi`、`1Gi`。

CPU 超过 limit 时通常表现为限速；内存超过 limit 时，容器可能被 OOM Kill，并根据 Pod 的重启策略进行后续处理。requests 不是实时使用量，也不表示容器只能使用这么多资源。

## 多容器资源计算

普通容器的 requests 会按资源类型求和，用于计算 Pod 调度时需要的资源。一个 Pod 内有多个容器时，每个容器都应按照自身职责分别配置资源。

```yaml [multi-container-resource-demo.yaml]
apiVersion: v1
kind: Pod
metadata:
  name: multi-container-resource-demo
spec:
  containers:
    - name: app
      image: nginx:1.31-alpine
      resources:
        requests:
          cpu: 200m
          memory: 256Mi
        limits:
          cpu: 1000m
          memory: 512Mi
    - name: sidecar
      image: busybox:1.38
      command: ["/bin/sh", "-c", "while true; do sleep 3600; done"]
      resources:
        requests:
          cpu: 50m
          memory: 64Mi
        limits:
          cpu: 100m
          memory: 128Mi
```

这个 Pod 没有 Init Container，因此调度请求值是两个普通容器 requests 之和，即 `250m` CPU 和 `320Mi` 内存。

如果 Pod 同时包含 Init Container，调度时会按每种资源分别比较“所有普通容器 requests 总和”和“单个 Init Container requests 最大值”，取较大者作为 Pod 的有效请求值。

## 节点存在空闲资源仍提示资源不足

Pod 调度失败时，`kubectl describe pod` 的 Events 中可能出现以下信息：

```text
0/3 nodes are available: 3 Insufficient cpu.
0/3 nodes are available: 3 Insufficient memory.
```

这类提示并不表示节点操作系统层面已经没有可用 CPU 或内存，而是表示从 Kubernetes 调度视角看，节点剩余可分配资源已经无法满足新 Pod 的 requests。Scheduler 判断节点是否可用时使用的是：

```text
节点 Allocatable - 已分配 requests >= 新 Pod requests
```

其中的“已分配”不是实时使用量，而是节点上所有未终止 Pod 声明的 requests 总和。因此，即便节点 CPU 使用率较低，也可能因为 requests 已经分配完而无法调度新 Pod。

## 排查步骤

### 查看 Pod 调度事件

先查看 Pod 为什么没有完成调度：

```bash
kubectl describe pod <pod-name>
```

重点关注 Events 区域。如果出现 `Insufficient cpu`、`Insufficient memory`，说明调度器认为节点剩余可分配资源不足。

### 查看节点容量与已分配资源

使用 `kubectl describe node` 查看某个节点的资源信息：

```bash
kubectl describe node <node-name>
```

重点关注：

- `Capacity`：节点总容量
- `Allocatable`：可分配给 Pod 的资源
- `Non-terminated Pods`：当前未终止的 Pod
- `Allocated resources`：已经被 requests 和 limits 声明占用的资源

::: details 输出类似如下

```text
Capacity:
  cpu:                2
  ephemeral-storage:  29751268Ki
  hugepages-1Gi:      0
  hugepages-2Mi:      0
  memory:             3960844Ki
  pods:               110
Allocatable:
  cpu:                2
  ephemeral-storage:  27418768544
  hugepages-1Gi:      0
  hugepages-2Mi:      0
  memory:             3858444Ki
  pods:               110
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests   Limits
  --------           --------   ------
  cpu                100m (5%)  500m (25%)
  memory             64Mi (1%)  128Mi (3%)
  ephemeral-storage  0 (0%)     0 (0%)
  hugepages-1Gi      0 (0%)     0 (0%)
  hugepages-2Mi      0 (0%)     0 (0%)
```

:::

这段输出需要重点区分：

- `Capacity` 是节点硬件或虚拟机的总资源
- `Allocatable` 是扣除系统组件、kubelet 保留资源后，可分配给 Pod 的资源
- `Allocated resources` 统计的是 Pod 声明的 requests 和 limits，不是实时使用量

如果 `Allocated resources` 中 CPU requests 已经接近 `Allocatable`，即使节点实时 CPU 使用率很低，新 Pod 仍可能因为 `Insufficient cpu` 无法调度。

### 查看节点实时使用量

集群部署 Metrics Server 后，可以使用 `kubectl top node` 查看节点实时资源使用情况：

```bash
kubectl top node
```

如果命令提示 `Metrics API not available`，先回到集群初始化记录中检查 Metrics Server、`v1beta1.metrics.k8s.io` APIService 和 kubelet `10250` 端口连通性。

::: details 输出类似如下

```text
NAME     CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
work01   220m         5%     1600Mi          22%
work02   180m         4%     1400Mi          19%
```

:::

`kubectl top node` 反映的是当前实际使用量，适合判断节点运行压力；`kubectl describe node` 中的 `Allocated resources` 反映的是 requests 和 limits 的声明占用，适合判断调度器为什么拒绝调度。

两者关注的问题不同：

| 命令                      | 关注点                                      | 典型用途           |
|-------------------------|------------------------------------------|----------------|
| `kubectl describe node` | Capacity、Allocatable、已分配 requests/limits | 排查 Pod 为什么无法调度 |
| `kubectl top node`      | 节点实时 CPU、内存使用率                           | 判断节点当前运行压力     |
| `free -h`               | Linux 操作系统内存使用情况                         | 判断节点系统层面的内存状态  |

### 理解 free -h 与调度结果的差异

登录节点后执行：

```bash
free -h
```

::: details 输出类似如下

```text
               total        used        free      shared  buff/cache   available
Mem:           3.8Gi       1.6Gi       266Mi       3.8Mi       2.1Gi       2.1Gi
Swap:             0B          0B          0B
```

:::

`free -h` 展示的是操作系统当前内存使用情况，其中 `available` 表示系统层面可用于新进程的估算内存。它不理解 Kubernetes Pod 的 requests，也不会统计调度器已经为 Pod 预留了多少资源。

因此可能出现以下情况：

```text
free -h 显示 available 还有 5Gi
kubectl describe node 显示 memory requests 已经达到 96%
新 Pod 请求 1Gi 内存后调度失败
```

原因是 Scheduler 按 requests 做预留式调度，避免把过多 Pod 调度到同一个节点；Linux 则只展示当前实际使用情况。调度失败时应以 `kubectl describe node` 的 Allocatable 和 Allocated resources 为准，而不是只看 `free -h`。

## 配置建议

生产环境应尽量为每个容器配置 requests 和 limits。requests 按服务稳定运行所需资源设置，limits 按服务可接受的峰值资源设置。CPU limit 过小会导致应用被限速，内存 limit 过小则可能触发 OOM Kill。
