# Job 资源与状态

Job 表示一个最终会结束的任务。Job 控制器创建 Pod，并持续协调成功数量、并行度、失败重试和截止时间；达到完成条件后把 Job 标记为 `Complete`，无法继续满足目标时标记为 `Failed`。

## 最小 Job

```yaml [hello-job.yaml]
apiVersion: batch/v1
kind: Job
metadata:
  name: hello
spec:
  backoffLimit: 3
  ttlSecondsAfterFinished: 600
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: hello
          image: busybox:1.38
          command: ["sh", "-c", "echo 'hello from Job'"]
```

```bash
kubectl create -f hello-job.yaml
kubectl get job hello
kubectl get pod -l batch.kubernetes.io/job-name=hello
kubectl logs job/hello
```

Job 的 Pod 模板必须设置 `restartPolicy: Never` 或 `OnFailure`，不能使用 `Always`。控制器会自动生成 Pod 选择器和 `batch.kubernetes.io/job-name` 等标签，普通 Job 不应手工编写 `spec.selector`。

## 关键字段

| 字段                        | 作用                                              |
|---------------------------|-------------------------------------------------|
| `completions`             | 需要成功完成的数量；固定完成数任务应显式设置                          |
| `parallelism`             | 同时运行 Pod 的目标上限，未设置时通常为 1                        |
| `completionMode`          | `NonIndexed` 或 `Indexed`，固定完成数任务默认 `NonIndexed` |
| `backoffLimit`            | Job 允许的失败重试上限，默认 6                              |
| `activeDeadlineSeconds`   | Job 从开始到终止的总时限，优先于 `backoffLimit`               |
| `ttlSecondsAfterFinished` | Job 完成或失败后保留多久再级联删除                             |
| `suspend`                 | 暂停或恢复 Job；暂停时会终止尚未完成的活动 Pod                     |

不设置 `completions` 和 `parallelism` 的普通 Job 通常运行一个 Pod，并在它成功后完成。并行工作队列可以只设置 `parallelism` 而省略 `completions`，但 Pod 必须通过外部队列协调取件和结束，不能把这种模式理解为固定成功次数。

Kubernetes v1.35 起，`spec.managedBy` 已稳定，可把特定 Job 交给外部控制器协调。字段省略或设为保留值 `kubernetes.io/job-controller` 时仍由内置 Job 控制器管理；自定义值必须对应已安装的外部控制器，并且创建后不可变。普通 Job 不应设置该字段，否则可能长期没有控制器创建 Pod；集群降级前还要确认旧版本不会与外部控制器同时管理同一对象。

## 状态字段

```bash
kubectl get job hello -o wide
kubectl describe job hello
kubectl get job hello -o yaml
```

常见计数包括：

- `status.active`：当前活动 Pod 数量。
- `status.terminating`：已经设置删除时间戳、但尚未到达终态的 Pod 数量。
- `status.succeeded`：成功 Pod 数量。
- `status.failed`：失败 Pod 数量。
- `status.completedIndexes`：Indexed Job 已成功的索引区间。
- `status.failedIndexes`：配置逐索引重试后，最终失败的索引区间。
- `status.conditions`：`Complete`、`Failed`、`Suspended` 等条件。

Kubernetes v1.31 及以后，Job 控制器会在所有相关 Pod 终止后才添加最终的 `Complete` 或 `Failed` 条件。成功或失败标准刚触发时可能先看到 `SuccessCriteriaMet` 或 `FailureTarget`，不能在仍有终止中 Pod 时假定资源已经完全释放。

## Pod 与日志

一个 Job 可能因重试产生多个 Pod，`kubectl logs job/<name>` 只适合快速查看单个匹配 Pod。排查失败历史时先列出全部 Pod，再逐个查看：

```bash
kubectl get pod -l batch.kubernetes.io/job-name=hello \
  --sort-by=.metadata.creationTimestamp
kubectl logs <job-pod-name>
kubectl describe pod <job-pod-name>
```

使用 `restartPolicy: Never` 时，每次失败通常保留为独立 Pod，更便于查看前一次退出状态；使用 `OnFailure` 时，容器可能在同一 Pod 中重启，应通过 `kubectl logs --previous` 查看上一次容器日志。

## 修改与重新执行

Job 的 Pod 模板大部分字段不可变。命令、镜像或环境变量变化时，通常删除并用新名称创建 Job，而不是原地修改；`suspend`、部分调度指令和并行度等字段有各自的可变规则。

已经成功或失败的 Job 不会自动从头再执行。需要保留历史时创建新名称：

保留原始清单，修改 `metadata.name` 后重新创建。kubectl 的 `create job --from` 用于从 CronJob 模板创建一次性 Job，不支持从普通 Job 克隆。

## 删除

```bash
kubectl delete job hello
```

删除 Job 默认会级联删除它管理的 Pod。正在执行的业务写入可能因此中断，删除前应先确认外部系统是否支持重试和幂等恢复。
