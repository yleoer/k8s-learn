# Deployment

Deployment 是 Kubernetes 中最常用的无状态工作负载控制器。它通过声明式配置描述应用期望状态，再由控制器自动维护副本数量、滚动发布版本，并在异常时提供回滚能力。

本节将原无状态调度章节合并为一个完整的 Deployment 文档，内容包括无状态调度基础、Deployment 定义与创建、更新与回滚、扩缩容与策略。

## 无状态调度基础

直接创建 Pod 有助于理解 Kubernetes 的最小运行单元，但生产环境通常不会长期使用裸 Pod 承载业务。Pod 退出后不会自动维持副本数，也缺少滚动更新、版本回滚和统一扩缩容能力。

Kubernetes 提供了一组工作负载控制器，用于持续维护业务期望状态。无状态服务通常使用 Deployment，有状态服务通常使用 StatefulSet，节点级守护进程通常使用 DaemonSet。

### 无状态服务

无状态服务指服务实例本身不保存必须依赖本地副本的数据。任意副本都可以处理请求，副本销毁后也不会造成业务数据丢失。

常见无状态服务包括：

- 前端静态页面服务
- 后端 API 服务
- 网关服务
- 不依赖本地持久化状态的微服务

无状态并不表示服务不需要数据，而是业务状态应存放在数据库、缓存、对象存储或其他外部系统中。这样 Pod 才可以被替换、扩容、缩容和迁移，Deployment 的滚动发布和故障自愈能力才能充分发挥。

### 工作负载控制器

常见调度资源可以按业务形态划分：

| 资源 | 典型场景 | 核心能力 |
| --- | --- | --- |
| `Deployment` | Web 服务、API 服务、微服务 | 多副本、滚动更新、回滚、扩缩容 |
| `ReplicaSet` | Deployment 底层副本控制 | 维持 Pod 副本数量 |
| `ReplicationController` | 早期副本控制器 | 维持 Pod 副本数量 |
| `StatefulSet` | 数据库、注册中心、有序集群 | 稳定网络标识、稳定存储、有序发布 |
| `DaemonSet` | 日志采集、监控 Agent、节点插件 | 在每个匹配节点运行一个 Pod |
| `Job` | 一次性任务 | 执行完成即退出 |
| `CronJob` | 周期性任务 | 按计划创建 Job |

本章聚焦常用工作负载调度，重点学习 Deployment、StatefulSet 和 DaemonSet。Job 和 CronJob 将在后续章节展开。

### RC 与 ReplicaSet

ReplicationController 简称 RC，是 Kubernetes 早期提供的副本控制器。它通过 `selector` 匹配一组 Pod，并维持匹配到的 Pod 数量等于 `spec.replicas`。

ReplicaSet 简称 RS，是 RC 的下一代实现。它同样用于维持 Pod 副本数，但支持更丰富的标签选择器。

| 对比项 | ReplicationController | ReplicaSet |
| --- | --- | --- |
| API 版本 | `v1` | `apps/v1` |
| 主要职责 | 维持 Pod 副本数量 | 维持 Pod 副本数量 |
| 标签选择器 | 等值匹配 | 等值匹配与集合表达式 |
| 当前定位 | 早期资源，了解即可 | Deployment 底层资源 |
| 生产建议 | 不建议新建使用 | 由 Deployment 自动管理 |

ReplicaSet 支持 `matchLabels` 和 `matchExpressions`：

```yaml
selector:
  matchLabels:
    app: nginx
  matchExpressions:
    - key: tier
      operator: In
      values:
        - frontend
```

现代 Kubernetes 中更常见的是 Deployment。Deployment 会自动创建和管理 ReplicaSet，再由 ReplicaSet 管理 Pod，因此实际使用中通常不直接操作 ReplicaSet 或 ReplicationController。

### RS 与 Pod 的关系

ReplicaSet 通过标签选择器关联 Pod，并不直接记录某几个 Pod 的名称。控制器持续观察匹配标签的 Pod 数量：实际数量少于期望值时创建新 Pod，多于期望值时删除多余 Pod。

下面示例使用 ReplicaSet 创建 3 个 Pod：

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: nginx-rs
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx-rs
  template:
    metadata:
      labels:
        app: nginx-rs
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
          ports:
            - containerPort: 80
```

创建并查看：

```bash
kubectl create -f nginx-rs.yaml
kubectl get rs
kubectl get pod -l app=nginx-rs -o wide
```

删除一个被 RS 管理的 Pod：

```bash
kubectl delete pod -l app=nginx-rs
kubectl get pod -l app=nginx-rs -w
```

ReplicaSet 会重新创建新的 Pod，使副本数量回到 3。如果要真正删除这组 Pod，应删除控制器：

```bash
kubectl delete rs nginx-rs
```

### Deployment 的定位

Deployment 是 Kubernetes 中最常用的无状态工作负载控制器。它以声明式方式描述应用期望状态，控制器自动完成 Pod 副本维护、滚动更新、版本回滚和扩缩容。

Deployment、ReplicaSet 和 Pod 的关系可以概括为：

```text
Deployment -> ReplicaSet -> Pod
```

用户一般创建 Deployment。Deployment 根据 Pod 模板创建 ReplicaSet，ReplicaSet 再根据副本数创建 Pod。发布新版本时，Deployment 会创建新的 ReplicaSet，并逐步调整新旧 ReplicaSet 的副本数量。

排查 Deployment 时，除了查看 Deployment 本身，还需要同时观察下层 RS 和 Pod：

```bash
kubectl get deploy
kubectl get rs
kubectl get po
```

## Deployment 定义与创建

Deployment 的核心配置集中在 `metadata`、`spec.selector` 和 `spec.template`。其中 `spec.template` 是 Pod 模板，决定了 Deployment 创建的 Pod 的具体形态。

只要 Pod 模板发生变化，Deployment 就会触发新版本发布。仅修改 `replicas` 不会创建新版本，因为副本数变化不属于 Pod 模板变化。

### 最小示例

下面是一个最小可用 Deployment：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deploy
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx-deploy
  template:
    metadata:
      labels:
        app: nginx-deploy
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
          ports:
            - containerPort: 80
```

创建并查看：

```bash
kubectl create -f nginx-deploy.yaml
kubectl get deploy
kubectl get rs
kubectl get po -l app=nginx-deploy -o wide
```

也可以用命令快速生成模板：

```bash
kubectl create deploy nginx-deploy --image=nginx:1.25 --dry-run=client -o yaml
```

生成的模板通常还需要补充 `replicas`、标签、端口、资源限制、探针和更新策略，才能接近生产可用配置。

### 基础字段

| 字段 | 是否必选 | 说明 |
| --- | --- | --- |
| `apiVersion` | 是 | Deployment 使用 `apps/v1` |
| `kind` | 是 | 资源类型，固定为 `Deployment` |
| `metadata.name` | 是 | Deployment 名称，同一 Namespace 内唯一 |
| `spec.replicas` | 否 | 期望副本数，默认值为 1 |
| `spec.selector` | 是 | 用于匹配下层 Pod 的标签选择器 |
| `spec.template` | 是 | Pod 模板 |
| `spec.template.metadata.labels` | 是 | Pod 标签，必须能被 selector 匹配 |
| `spec.template.spec.containers` | 是 | 容器列表 |

Deployment 的 `spec.selector.matchLabels` 必须匹配 Pod 模板中的标签：

```yaml
selector:
  matchLabels:
    app: nginx
template:
  metadata:
    labels:
      app: nginx
```

如果二者不匹配，创建时会失败。创建成功后，`spec.selector` 通常不可修改，因此前期应规划好稳定标签。

### 常用增强配置

生产中常见的 Deployment 还会补充资源限制、健康检查、更新策略和历史版本保留：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 3
  revisionHistoryLimit: 5
  selector:
    matchLabels:
      app: nginx
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
          ports:
            - name: http
              containerPort: 80
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
          readinessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 15
            periodSeconds: 20
```

生产中的 Deployment 不应只包含镜像和副本数，还应逐步补齐 `resources`、`readinessProbe`、`livenessProbe`、`startupProbe`、`strategy`、`revisionHistoryLimit` 以及优雅退出配置。

### 创建过程

创建 Deployment 后，Pod 并非由用户直接创建。Kubernetes 会通过控制器链路逐层生成资源：

| 步骤 | 组件 | 行为 |
| --- | --- | --- |
| 1 | APIServer | 接收 Deployment YAML 并保存到 etcd |
| 2 | Deployment Controller | 发现新 Deployment，创建对应 ReplicaSet |
| 3 | ReplicaSet Controller | 根据 `replicas` 创建 Pod |
| 4 | Scheduler | 为 Pending 状态的 Pod 选择节点 |
| 5 | kubelet | 在目标节点拉取镜像并启动容器 |
| 6 | kubelet | 上报 Pod 状态，控制器继续对齐期望状态 |

Pod 名称通常包含 ReplicaSet 名称前缀，例如：

```text
nginx-deploy-596cdb74d9-2s4kc
```

其中 `nginx-deploy-596cdb74d9` 是 ReplicaSet 名称，最后一段是 Pod 随机后缀。

### 状态字段

查看 Deployment：

```bash
kubectl get deploy nginx-deploy
```

示例输出：

```text
NAME           READY   UP-TO-DATE   AVAILABLE   AGE
nginx-deploy   3/3     3            3           17s
```

| 字段 | 说明 |
| --- | --- |
| `READY` | 就绪副本数与期望副本数，例如 `3/3` |
| `UP-TO-DATE` | 已经更新到最新模板版本的副本数 |
| `AVAILABLE` | 可用副本数，通常表示已就绪并满足最小可用时间 |
| `AGE` | Deployment 创建时长 |

查看发布进度：

```bash
kubectl rollout status deploy nginx-deploy
```

查看完整状态和事件：

```bash
kubectl get deploy nginx-deploy -o yaml
kubectl describe deploy nginx-deploy
```

如果 Deployment 显示未就绪，可以继续查看下层资源：

```bash
kubectl get rs -l app=nginx-deploy
kubectl get po -l app=nginx-deploy
kubectl describe po <pod-name>
```

Deployment 状态用于判断发布整体是否成功，Pod 状态用于定位具体失败原因。排查时应从 Deployment 向下逐层展开。

## Deployment 更新与回滚

Deployment 的更新由 Pod 模板变化触发。常见触发点包括镜像版本、环境变量、启动命令、资源限制、探针以及模板的标签和注解等字段。

仅修改 `spec.replicas` 不会触发新版本发布，因为副本数不属于 Pod 模板。

### 更新镜像

先创建基础 Deployment：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-update
  annotations:
    kubernetes.io/change-cause: "create nginx 1.25"
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx-update
  template:
    metadata:
      labels:
        app: nginx-update
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
```

创建资源：

```bash
kubectl create -f nginx-update.yaml
kubectl rollout status deploy nginx-update
```

更新镜像：

```bash
kubectl set image deploy nginx-update nginx=nginx:1.26
kubectl rollout status deploy nginx-update
kubectl annotate deploy nginx-update kubernetes.io/change-cause="update nginx to 1.26" --overwrite
```

先触发镜像更新并等待发布完成，再修改 `kubernetes.io/change-cause`，可以将说明更新到当前最新 revision 上。

::: warning 注意

不要在 `kubectl set image` 之前执行 `kubectl annotate ... --overwrite`。Deployment 控制器可能会把新的 `change-cause` 同步到当前活跃 ReplicaSet，导致旧 revision 的说明被覆盖。

:::

查看新旧 ReplicaSet：

```bash
kubectl get rs -l app=nginx-update
```

::: details 示例输出

```bash
$ kubectl get rs -l app=nginx-update
NAME                      DESIRED   CURRENT   READY   AGE
nginx-update-69d468d65b   0         0         0       4m12s
nginx-update-859c676bc    3         3         3       3m6s
```

:::

更新完成后，新的 RS 副本数会变为 3，旧的 RS 副本数会变为 0。旧 RS 通常仍会保留，用于后续回滚。

生产中更推荐修改 YAML 后使用 `apply`：

```bash
kubectl apply -f nginx-update.yaml
kubectl rollout status deploy nginx-update
```

这种方式适合与 Git 版本控制结合，便于审计变更来源。

#### 更新未触发的常见原因

| 现象 | 原因 |
| --- | --- |
| 修改 `replicas` 后没有新 RS | 副本数不属于 Pod 模板 |
| 修改 Deployment 注解后没有新 RS | 只修改 Deployment 自身元数据，不影响 Pod 模板 |
| 修改 `spec.template.metadata.annotations` 后有新 RS | Pod 模板元数据发生变化 |
| 镜像 tag 相同但内容变了 | Kubernetes 无法感知镜像内容变化，建议使用不可变 tag |

如果需要强制重启一组 Pod，可以使用：

```bash
kubectl rollout restart deploy nginx-update
```

该命令会更新 Pod 模板注解，从而触发一次滚动更新。

### 查看历史版本

Deployment 发布新版本时会保留历史 ReplicaSet。只要历史版本没有被清理，就可以使用 `kubectl rollout undo` 回退到上一个版本或指定版本。

查看历史版本：

```bash
kubectl rollout history deploy nginx-update
```

更新镜像并记录变更说明：

```bash
kubectl set image deploy nginx-update nginx=nginx:1.27
kubectl rollout status deploy nginx-update
kubectl annotate deploy nginx-update kubernetes.io/change-cause="update nginx to 1.27" --overwrite
```

再次查看历史版本，可以直观查看每个 revision 对应的变更原因：

```bash
kubectl rollout history deploy nginx-update
```

示例输出：

```text
deployment.apps/nginx-update
REVISION  CHANGE-CAUSE
1         create nginx 1.25
2         update nginx to 1.26
3         update nginx to 1.27
```

查看指定版本详情：

```bash
kubectl rollout history deploy nginx-update --revision=3
```

`CHANGE-CAUSE` 来自 `kubernetes.io/change-cause` 注解。生产中建议在变更流程中记录清晰的说明，方便快速判断每个版本的来源。

### 版本回滚

回滚到上一个版本：

```bash
kubectl rollout undo deploy nginx-update
kubectl rollout status deploy nginx-update
```

回滚到指定 revision：

```bash
kubectl rollout undo deploy nginx-update --to-revision=2
kubectl rollout status deploy nginx-update
```

::: details 示例

```bash
$ kubectl rollout undo deploy nginx-update
deployment.apps/nginx-update rolled back

$ kubectl describe po -l app=nginx-update | grep Image:
    Image:          nginx:1.26
    Image:          nginx:1.26
    Image:          nginx:1.26

$ kubectl rollout history deploy nginx-update
deployment.apps/nginx-update
REVISION  CHANGE-CAUSE
1         create nginx 1.25
3         update nginx to 1.27
4         update nginx to 1.26


$ kubectl rollout undo deploy nginx-update --to-revision=1
deployment.apps/nginx-update rolled back

$ kubectl describe po -l app=nginx-update | grep Image:
    Image:          nginx:1.25
    Image:          nginx:1.25
    Image:          nginx:1.25

$ kubectl rollout history deploy nginx-update
deployment.apps/nginx-update
REVISION  CHANGE-CAUSE
3         update nginx to 1.27
4         update nginx to 1.26
5         create nginx 1.25
```

:::

回滚本身也会形成新的 revision，因此历史编号会继续递增。

需要注意：

- 只能回滚 Deployment 的 Pod 模板历史，不能回滚 Service、ConfigMap、Secret 等外部资源
- 如果历史 ReplicaSet 被 `revisionHistoryLimit` 清理，就无法回滚到对应版本
- 使用 `latest` 这类可变镜像 tag 会降低回滚可控性
- 回滚前应确认数据库变更、配置变更和兼容性问题是否可逆

### 暂停和恢复

Deployment 默认在 Pod 模板发生变化后立即触发滚动更新。如果一次发布需要连续修改镜像、环境变量、资源限制和探针，可以先暂停 Deployment，完成多项修改后再恢复更新。

暂停发布：

```bash
kubectl rollout pause deploy nginx-update
```

暂停后继续修改 Pod 模板：

```bash
kubectl set image deploy nginx-update nginx=nginx:1.28
kubectl set env deploy nginx-update APP_ENV=prod
kubectl set resources deploy nginx-update -c=nginx --requests=cpu=100m,memory=128Mi --limits=cpu=500m,memory=256Mi
```

恢复发布：

```bash
kubectl rollout resume deploy nginx-update
kubectl rollout status deploy nginx-update
kubectl annotate deploy nginx-update kubernetes.io/change-cause="update nginx to 1.28 and app env" --overwrite
```

恢复后，Deployment 会把暂停期间积累的 Pod 模板修改合并成一次新版本发布。

### 历史版本保留

`revisionHistoryLimit` 用于控制 Deployment 保留多少个旧版本：

```yaml
spec:
  revisionHistoryLimit: 5
```

常见取值为 5 到 10。版本保留数量需要结合发布频率、回滚要求和集群规模确定。不要把 Deployment 历史版本当作唯一回滚手段，可靠的回滚还应包括 Git 中的 YAML、不可变镜像 tag、配置变更记录和数据库变更预案。

## Deployment 扩缩容与策略

Deployment 通过 `spec.replicas` 控制期望副本数。扩容会创建更多 Pod，缩容会删除多余 Pod。副本数变化不会产生新的历史版本。

Deployment 还通过 `spec.strategy` 控制更新方式。常用策略有 RollingUpdate 和 Recreate，默认策略是 RollingUpdate。

### 手动扩缩容

创建示例 Deployment：

```bash
kubectl create deploy nginx-scale --image=nginx:1.25
kubectl scale deploy nginx-scale --replicas=3
kubectl rollout status deploy nginx-scale
```

扩容到 5 个副本：

```bash
kubectl scale deploy nginx-scale --replicas=5
kubectl get pod -l app=nginx-scale -o wide
```

缩容到 2 个副本：

```bash
kubectl scale deploy nginx-scale --replicas=2
kubectl get deploy nginx-scale
```

也可以修改 YAML 中的 `spec.replicas` 后执行：

```bash
kubectl apply -f nginx-scale.yaml
```

生产中更推荐通过 YAML 或发布平台管理副本数，避免手动命令造成配置漂移。

### 容量评估

扩容前应关注节点资源：

```bash
kubectl describe node <node-name>
kubectl top node
kubectl top pod
```

重点确认：

- 节点 Allocatable 是否还能满足新 Pod 的 requests
- 服务下游数据库、缓存、消息队列是否能承受更多实例
- Service、Ingress 或网关是否能正常发现新 Pod
- 应用是否真正无状态，新增副本是否可以立即处理请求

如果 Pod 一直 Pending，优先查看事件：

```bash
kubectl describe pod <pod-name>
```

常见原因包括 CPU 或内存不足、节点选择器不匹配、污点未容忍，或者镜像拉取失败。

### 缩容注意事项

缩容会删除一部分 Pod。为了降低请求中断风险，服务应具备：

| 配置 | 作用 |
| --- | --- |
| `readinessProbe` | 缩容或退出前从服务流量中摘除异常 Pod |
| `preStop` | 退出前执行下线、等待或通知动作 |
| `terminationGracePeriodSeconds` | 给进程处理存量请求的时间 |

示例：

```yaml
spec:
  template:
    spec:
      terminationGracePeriodSeconds: 30
      containers:
        - name: app
          image: nginx:1.25
          lifecycle:
            preStop:
              exec:
                command: ["sh", "-c", "sleep 10"]
```

### 更新策略

| 策略 | 行为 | 适用场景 |
| --- | --- | --- |
| `RollingUpdate` | 逐步创建新 Pod 并删除旧 Pod | 多数无状态服务，追求发布期间保持可用 |
| `Recreate` | 先删除全部旧 Pod，再创建新 Pod | 无法容忍新旧版本共存的服务 |

RollingUpdate 可以在发布过程中保持部分旧版本继续服务，同时逐步引入新版本。Recreate 会产生明显中断，但能避免新旧版本同时运行。

常见 RollingUpdate 配置：

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 0
```

字段说明：

| 字段 | 说明 |
| --- | --- |
| `maxSurge` | 更新期间允许超出期望副本数的最大 Pod 数量 |
| `maxUnavailable` | 更新期间允许不可用的最大 Pod 数量 |

`maxSurge` 和 `maxUnavailable` 可以使用整数或百分比。对核心服务而言，通常建议从 `maxUnavailable: 0` 开始，再根据容量和发布速度进行调整。

### 滚动更新过程

以 4 副本、`maxSurge: 1`、`maxUnavailable: 0` 为例，更新时大致过程如下：

| 阶段 | 行为 |
| --- | --- |
| 1 | 创建新 ReplicaSet |
| 2 | 新 RS 增加 1 个 Pod，副本总数临时变为 5 |
| 3 | 新 Pod Ready 后，旧 RS 减少 1 个 Pod |
| 4 | 重复扩新缩旧，直到新 RS 达到 4 个副本 |
| 5 | 旧 RS 副本数归零，发布完成 |

观察过程：

```bash
kubectl set image deploy nginx-scale nginx=nginx:1.26
kubectl get deploy nginx-scale -w
kubectl get rs -l app=nginx-scale
```

滚动更新依赖 readiness 状态判断新 Pod 是否可以接收流量。未配置 readinessProbe 时，容器启动后可能很快被视为 Ready，但应用内部尚未完成初始化。

### Recreate 策略

Recreate 配置如下：

```yaml
strategy:
  type: Recreate
```

使用 Recreate 时不能配置 `rollingUpdate`。更新过程会先删除旧 Pod，再创建新 Pod，因此服务可能短暂不可用。

Recreate 可以用于以下场景：

- 应用新旧版本不能同时访问同一外部资源
- 单副本内部管理任务，短暂中断可接受
- 学习环境中希望清晰观察删除再创建过程
- 业务已经在上层网关、队列或发布流程中处理了中断影响

如果服务面向用户请求，优先考虑 RollingUpdate。如果新旧版本不能共存，更推荐改造应用兼容性或设计灰度方案，而不是长期依赖 Recreate。

### 发布建议

- 使用不可变镜像 tag，例如 Git commit、构建号或语义化版本
- 配置 readinessProbe，避免未就绪 Pod 提前接流量
- 配置优雅退出，避免旧 Pod 删除时中断请求
- 保留合理历史版本，确保异常后可回滚
- 发布前确认节点资源能够承载 `maxSurge` 带来的额外 Pod

滚动更新只是 Kubernetes 的执行机制，业务是否真正无损还依赖应用自身兼容性。例如接口字段、数据库结构、缓存协议和消息格式都应支持新旧版本短时间共存。
