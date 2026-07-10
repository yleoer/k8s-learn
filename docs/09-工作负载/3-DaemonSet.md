# DaemonSet

DaemonSet 用于在每个匹配节点上运行一份 Pod 副本。它不以业务副本数为中心，而是以节点覆盖为中心，适合日志采集、监控 Agent、网络插件和存储插件等节点级组件。

本文将 DaemonSet 相关内容合并为一个文档，内容包括定义与创建、更新回滚、指定节点部署和常见排查方法。

## DaemonSet 定义与创建

当新节点加入集群时，DaemonSet 会自动在该节点上创建 Pod。当节点从集群中移除时，该节点上的 Pod 也会随节点生命周期消失。删除 DaemonSet 时，它创建的 Pod 会被一起删除。

### 适用场景

DaemonSet 常用于以下场景：

- 每个节点运行日志采集进程，例如 Fluentd、Filebeat、Vector
- 每个节点运行监控进程，例如 Prometheus Node Exporter
- 每个节点运行网络组件，例如 CNI 插件 Agent
- 每个节点运行存储组件，例如 Ceph、GlusterFS 或 CSI 节点插件
- 每个匹配节点运行安全、审计或巡检进程

这些组件通常需要访问节点本地日志、网络、设备、文件系统或运行时信息。如果使用 Deployment，就需要额外控制副本与节点的分布关系；DaemonSet 则天然表达“每个匹配节点一个”的意图。

### 与其他控制器对比

| 控制器         | 调度目标                | 典型场景            |
|-------------|---------------------|-----------------|
| Deployment  | 指定副本数，调度到合适节点       | Web、API、微服务     |
| StatefulSet | 指定副本数，并保持稳定身份       | 数据库、注册中心、协调组件   |
| DaemonSet   | 稳定状态下每个匹配节点运行一个 Pod | 日志、监控、网络、存储节点组件 |

DaemonSet 不需要配置 `replicas`。副本数量由符合条件的节点数量决定，滚动更新期间可能因 `maxSurge` 临时增加。

### 最小示例

下面示例使用 DaemonSet 在每个匹配节点稳定运行一个 Nginx Pod：

```yaml [node-nginx-daemonset.yaml]
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-nginx
  labels:
    app: node-nginx
spec:
  selector:
    matchLabels:
      app: node-nginx
  template:
    metadata:
      labels:
        app: node-nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.31-alpine
          ports:
            - name: http
              containerPort: 80
```

创建并查看：

```bash
kubectl create -f node-nginx-daemonset.yaml
kubectl get ds
kubectl get pod -l app=node-nginx -o wide
```

如果集群有 3 个可调度节点，并且没有其他限制条件，通常会看到 3 个 Pod，分别运行在不同节点上。

### 核心字段

| 字段                                | 是否必选 | 说明                       |
|-----------------------------------|------|--------------------------|
| `apiVersion`                      | 是    | DaemonSet 使用 `apps/v1`   |
| `kind`                            | 是    | 资源类型，固定为 `DaemonSet`     |
| `metadata.name`                   | 是    | DaemonSet 名称             |
| `spec.selector`                   | 是    | 匹配 DaemonSet 管理的 Pod     |
| `spec.template`                   | 是    | Pod 模板                   |
| `spec.updateStrategy`             | 否    | 更新策略，默认是 `RollingUpdate` |
| `spec.template.spec.nodeSelector` | 否    | 限制 Pod 运行到指定标签节点         |
| `spec.template.spec.tolerations`  | 否    | 允许 Pod 调度到带污点的节点         |

与 Deployment 类似，`spec.selector.matchLabels` 必须匹配 `spec.template.metadata.labels`，否则创建请求会被 API 拒绝。DaemonSet 创建后 selector 不可修改。

### 创建过程

DaemonSet 创建 Pod 的过程可以概括为：

| 步骤 | 组件                               | 行为                                                                     |
|----|----------------------------------|------------------------------------------------------------------------|
| 1  | APIServer                        | 保存 DaemonSet 资源                                                        |
| 2  | DaemonSet Controller             | 观察符合条件的节点                                                              |
| 3  | DaemonSet Controller             | 为每个匹配节点创建 Pod                                                          |
| 4  | DaemonSet Controller / Scheduler | Controller 为 Pod 注入指向目标节点的 `nodeAffinity`；Scheduler 按该亲和性将 Pod 绑定到目标节点 |
| 5  | kubelet                          | 在目标节点启动容器                                                              |

DaemonSet 控制器会持续对齐节点与 Pod 的关系，并负责判断哪些节点应运行 DaemonSet Pod。某个节点上的 DaemonSet Pod 被删除后，控制器会重新创建一个新的 Pod。

验证自愈：

```bash
kubectl delete pod -l app=node-nginx
kubectl get pod -l app=node-nginx -w
```

Pod 删除后会被重新创建，稳定状态下每个匹配节点仍保持一个 Pod。

### 状态字段

查看 DaemonSet：

```bash
kubectl get ds node-nginx
```

::: details 输出类似如下

```text
NAME         DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
node-nginx   3         3         3       3            3           <none>          1m
```

:::

字段说明：

| 字段              | 说明                       |
|-----------------|--------------------------|
| `DESIRED`       | 期望运行 DaemonSet Pod 的节点数量 |
| `CURRENT`       | 当前已经创建 Pod 的节点数量         |
| `READY`         | Ready 状态的 Pod 数量         |
| `UP-TO-DATE`    | 已经使用最新模板的 Pod 数量         |
| `AVAILABLE`     | 可用 Pod 数量                |
| `NODE SELECTOR` | 节点选择条件                   |

如果 `DESIRED` 小于集群节点数量，通常是因为节点不可调度、节点标签不匹配、污点未容忍或调度条件限制。

### 常见增强配置

日志采集、监控和节点插件通常需要访问宿主机路径。下面示例挂载节点日志目录：

```yaml{24-32}
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-agent
spec:
  selector:
    matchLabels:
      app: log-agent
  template:
    metadata:
      labels:
        app: log-agent
    spec:
      containers:
        - name: agent
          image: <registry.example.com>/<namespace>/log-agent:1.0.0
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
          volumeMounts:
            - name: varlog
              mountPath: /var/log
              readOnly: true
      volumes:
        - name: varlog
          hostPath:
            path: /var/log
            type: Directory
```

使用 `hostPath` 时要格外谨慎。它会把节点文件系统暴露给容器，生产环境应配合最小权限、只读挂载、安全上下文和命名空间隔离使用。

### 注意事项

- DaemonSet 不配置 `replicas`，副本数由匹配节点数量决定
- 新节点加入后会自动创建对应 Pod
- 节点删除后，节点上的 Pod 会随节点消失
- 删除 DaemonSet 会删除它创建的 Pod
- 启用 `maxSurge` 更新时，同一节点可能短时间存在新旧两个 Pod
- 节点污点、节点标签、资源 requests 都会影响 DaemonSet 覆盖范围
- 节点级组件应配置资源限制，避免影响业务 Pod

DaemonSet 的排查重点不是“副本数是否等于配置值”，而是“哪些节点应该运行、哪些节点实际运行、未运行节点为什么不匹配”。

## DaemonSet 更新与节点选择

DaemonSet 的日常运维主要包括版本更新、异常回滚和节点范围控制。它运行在节点层面，影响面通常覆盖整个集群，因此更新前需要特别关注发布节奏、资源占用和节点选择条件。

相比 Deployment，DaemonSet 的副本不是面向业务容量，而是面向节点覆盖。排查时应把 Pod 状态与节点标签、污点、可调度状态一起观察。

### 更新策略

DaemonSet 通过 `spec.updateStrategy` 控制更新方式：

```yaml{9,10}
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: rolling-node-nginx
spec:
  selector:
    matchLabels:
      app: rolling-node-nginx
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        app: rolling-node-nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
```

常见策略如下：

| 策略              | 行为                      | 适用场景          |
|-----------------|-------------------------|---------------|
| `RollingUpdate` | Pod 模板变化后自动滚动替换旧 Pod    | 大多数 DaemonSet |
| `OnDelete`      | 模板变化后不自动替换，手动删除 Pod 才重建 | 需要人工逐节点确认的组件  |

默认策略是 `RollingUpdate`。更新镜像：

```bash
kubectl set image ds node-nginx nginx=nginx:1.28
kubectl rollout status ds node-nginx
```

查看更新历史：

```bash
kubectl rollout history ds node-nginx
```

查看新旧 Pod：

```bash
kubectl get pod -l app=node-nginx -o wide
```

DaemonSet 更新会逐步删除旧 Pod 并创建新 Pod。对于日志、监控、网络这类节点组件，建议在低峰期执行，并观察节点状态和组件指标。

### 滚动更新参数

DaemonSet RollingUpdate 支持 `maxUnavailable` 和 `maxSurge`，用于控制更新期间不可用 Pod 数量和临时新增 Pod 数量；`spec.minReadySeconds` 决定新 Pod 何时被视为可用：

```yaml{9-14}
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: rolling-param-node-nginx
spec:
  selector:
    matchLabels:
      app: rolling-param-node-nginx
  minReadySeconds: 30
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 0
  template:
    metadata:
      labels:
        app: rolling-param-node-nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
```

字段说明：

| 字段                             | 说明                                               |
|--------------------------------|--------------------------------------------------|
| `rollingUpdate.maxUnavailable` | 更新期间最多允许不可用的 DaemonSet Pod 数量，默认 1               |
| `rollingUpdate.maxSurge`       | 更新期间允许在已有可用 DaemonSet Pod 的节点上临时创建新 Pod 的数量，默认 0 |
| `spec.minReadySeconds`         | 新 Pod Ready 且无容器崩溃后需保持的最短秒数，达到后才计入可用，默认 0        |

`maxUnavailable` 和 `maxSurge` 可以是整数或百分比，百分比按更新开始时的 Pod 总数计算并向上取整（`maxSurge` 的换算结果最小为 1），二者不能同时为 0。

`spec.minReadySeconds` 与 `updateStrategy` 平级，不在 `rollingUpdate` 块内。设置后，控制器会在新 Pod Ready 后额外等待该时长才认定节点更新完成，再继续处理后续节点，为节点级组件提供观察窗口。可用性判断由控制面基于时间完成，节点与控制面时钟偏差过大时，滚动更新进度可能被误判。

配置 `maxSurge` 后，控制器可以先在节点上创建新 Pod，待新 Pod Ready 并满足 `minReadySeconds` 后，再删除该节点上的旧 Pod。这样能降低更新期间的空窗，但同一节点上可能短时间运行新旧两个 DaemonSet Pod。

资源开销较高或独占宿主机端口、设备、路径的 DaemonSet 通常不适合启用 `maxSurge`。如果启用，需要提前确认节点资源、端口绑定、hostPath 写入和应用互斥逻辑不会冲突。

如果组件在每个节点上都很关键，例如网络插件或存储插件，应结合组件自身建议设置更新策略，并提前确认集群控制面、业务流量和监控告警状态。

### 版本回滚

DaemonSet 支持回滚到上一个版本：

```bash
kubectl rollout undo ds node-nginx
kubectl rollout status ds node-nginx
```

回滚到指定 revision：

```bash
kubectl rollout history ds node-nginx
kubectl rollout undo ds node-nginx --to-revision=2
kubectl rollout status ds node-nginx
```

回滚本质上仍是一次新的滚动更新。对于节点级组件，回滚前应确认问题来自 Pod 模板变更，而不是节点资源、宿主机路径、权限或外部配置。

### OnDelete 策略

如果希望手动控制每个节点上的更新节奏，可以使用 `OnDelete`：

```yaml{9,10}
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ondelete-node-nginx
spec:
  selector:
    matchLabels:
      app: ondelete-node-nginx
  updateStrategy:
    type: OnDelete
  template:
    metadata:
      labels:
        app: ondelete-node-nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
```

修改 Pod 模板后，DaemonSet 不会自动删除旧 Pod。手动删除某个节点上的 Pod 后，新 Pod 才会按最新模板创建：

```bash
kubectl set image ds ondelete-node-nginx nginx=nginx:1.28
kubectl delete pod <daemonset-pod-name>
kubectl get pod -l app=ondelete-node-nginx -o wide
```

这种方式适合非常敏感的节点组件，例如每次只更新一个节点，并在业务和指标稳定后再继续下一个节点。

### 指定节点部署

DaemonSet 默认会覆盖所有符合调度条件的节点。可以通过 `nodeSelector` 只部署到带特定标签的节点。

给节点添加标签：

```bash
kubectl label node <node-name> node-role.example.com/logging=true
```

DaemonSet 配置：

```yaml{14,15}
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: logging-agent
spec:
  selector:
    matchLabels:
      app: logging-agent
  template:
    metadata:
      labels:
        app: logging-agent
    spec:
      nodeSelector:
        node-role.example.com/logging: "true"
      containers:
        - name: agent
          image: busybox:1.38
          command: ["/bin/sh", "-c", "tail -f /dev/null"]
```

查看部署结果：

```bash
kubectl get ds logging-agent
kubectl get pod -l app=logging-agent -o wide
```

移除节点标签：

```bash
kubectl label node <node-name> node-role.example.com/logging-
```

标签移除后，如果节点不再匹配 DaemonSet 条件，该节点上的 DaemonSet Pod 会被删除。

### 节点亲和性

`nodeSelector` 适合简单等值匹配。复杂条件可以使用节点亲和性：

```yaml{14-22}
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: logging-agent-affinity
spec:
  selector:
    matchLabels:
      app: logging-agent-affinity
  template:
    metadata:
      labels:
        app: logging-agent-affinity
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: node-role.example.com/logging
                    operator: In
                    values:
                      - "true"
      containers:
        - name: agent
          image: busybox:1.38
          command: ["/bin/sh", "-c", "tail -f /dev/null"]
```

节点亲和性支持 `In`、`NotIn`、`Exists`、`DoesNotExist` 等表达方式，适合按节点角色、机房、硬件能力或操作系统类型选择部署范围。

需要注意，`requiredDuringSchedulingIgnoredDuringExecution` 对普通 Pod 只在调度时生效，节点标签变化后已运行的 Pod 不会因此被驱逐。DaemonSet Pod 的行为不同：控制器会持续对齐节点匹配关系，节点标签变化后会及时在新匹配的节点上创建 Pod，并删除不再匹配节点上的 Pod。

### 污点与容忍

控制平面节点或专用节点通常带有污点。DaemonSet 如果需要运行到这些节点，需要配置 tolerations。

DaemonSet 控制器会自动为 Pod 添加一组容忍，包括 `node.kubernetes.io/not-ready`、`node.kubernetes.io/unreachable`、`node.kubernetes.io/disk-pressure`、`node.kubernetes.io/memory-pressure`、`node.kubernetes.io/pid-pressure` 和 `node.kubernetes.io/unschedulable`；`hostNetwork: true` 的 Pod 还会容忍 `node.kubernetes.io/network-unavailable`。因此节点被标记为不可调度或出现资源压力污点时，DaemonSet Pod 仍会照常调度和保留，这也是它区别于普通工作负载的重要行为。

查看节点污点：

```bash
kubectl describe node <node-name> | grep -i taints
```

容忍示例：

```yaml{14-17}
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: control-plane-agent
spec:
  selector:
    matchLabels:
      app: control-plane-agent
  template:
    metadata:
      labels:
        app: control-plane-agent
    spec:
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
      containers:
        - name: agent
          image: busybox:1.38
          command: ["/bin/sh", "-c", "tail -f /dev/null"]
```

如果希望日志或监控 Agent 覆盖控制平面节点，通常需要添加对应容忍。是否部署到控制平面节点应结合集群规模和安全策略决定。

### 排查方法

当 DaemonSet 没有覆盖预期节点时，可以按以下顺序检查：

```bash
kubectl get ds node-nginx -o wide
kubectl describe ds node-nginx
kubectl get node --show-labels
kubectl describe node <node-name>
kubectl get pod -l app=node-nginx -o wide
```

常见原因如下：

| 现象                   | 可能原因                | 处理方向                          |
|----------------------|---------------------|-------------------------------|
| `DESIRED` 小于节点数      | nodeSelector 或亲和性限制 | 检查节点标签和选择条件                   |
| Pod Pending          | 节点资源不足或污点未容忍        | 查看 Pod 事件和节点污点                |
| Pod CrashLoopBackOff | 进程启动失败              | 查看日志和启动参数                     |
| Pod Running 但功能异常    | 宿主机路径、权限或配置错误       | 检查 volume、securityContext 和配置 |
| 控制平面节点没有 Pod         | 未容忍控制平面污点           | 添加必要 tolerations              |

查看 Pod 事件时，复用 Pod 资源章节[查看 Pod 调度事件](../08-Pod入门/2-Pod资源分配与调度排查.md#查看-pod-调度事件)中的 `describe` 命令。

查看容器日志：

```bash
kubectl logs <pod-name>
```

DaemonSet 的排查要把控制器、Pod 和节点三者放在一起看。只看 Pod 数量容易遗漏节点标签、污点和可调度状态带来的影响。

### 清理资源

删除 DaemonSet：

```bash
kubectl delete ds node-nginx
```

删除测试用节点标签时，重新执行前文[指定节点部署](#指定节点部署)末尾的标签移除命令。

如果创建了临时镜像、ConfigMap、ServiceAccount 或 RBAC，也应一并清理。节点级组件经常涉及较高权限，测试完成后不要把无用权限长期留在集群中。

## 参考

- [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)
- [Perform a Rolling Update on a DaemonSet](https://kubernetes.io/docs/tasks/manage-daemon/update-daemon-set/)
- [DaemonSet API reference](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/daemon-set-v1/)
