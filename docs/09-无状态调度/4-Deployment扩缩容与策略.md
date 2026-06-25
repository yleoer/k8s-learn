# Deployment 扩缩容与策略

Deployment 通过 `spec.replicas` 控制期望副本数。扩容会创建更多 Pod，缩容会删除多余 Pod。副本数变化不会产生新的历史版本。

Deployment 还通过 `spec.strategy` 控制更新方式。常用策略有 RollingUpdate 和 Recreate，默认策略是 RollingUpdate。

## 手动扩缩容

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

## 容量评估

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

## 缩容注意事项

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

## 更新策略

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

## 滚动更新过程

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

## Recreate 策略

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

## 发布建议

- 使用不可变镜像 tag，例如 Git commit、构建号或语义化版本
- 配置 readinessProbe，避免未就绪 Pod 提前接流量
- 配置优雅退出，避免旧 Pod 删除时中断请求
- 保留合理历史版本，确保异常后可回滚
- 发布前确认节点资源能够承载 `maxSurge` 带来的额外 Pod

滚动更新只是 Kubernetes 的执行机制，业务是否真正无损还依赖应用自身兼容性。例如接口字段、数据库结构、缓存协议和消息格式都应支持新旧版本短时间共存。
