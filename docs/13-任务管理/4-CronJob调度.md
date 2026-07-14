# CronJob 调度

CronJob 按 Cron 表达式周期性创建 Job，Job 再管理 Pod。CronJob 只负责调度、并发策略和历史数量，不直接运行容器，也不保证每个计划时刻恰好创建一个 Job。

## 完整清单

```yaml [hello-cronjob.yaml]
apiVersion: batch/v1
kind: CronJob
metadata:
  name: hello
spec:
  schedule: "*/5 * * * *"
  timeZone: Asia/Shanghai
  concurrencyPolicy: Forbid
  startingDeadlineSeconds: 120
  suspend: false
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    metadata:
      labels:
        app.kubernetes.io/name: hello-cronjob
    spec:
      backoffLimit: 2
      activeDeadlineSeconds: 60
      ttlSecondsAfterFinished: 3600
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: hello
              image: busybox:1.38
              command:
                - sh
                - -c
                - date -u +%Y-%m-%dT%H:%M:%SZ
```

```bash
kubectl create -f hello-cronjob.yaml
kubectl get cj hello
kubectl get job -l app.kubernetes.io/name=hello-cronjob
```

CronJob 名称会用于派生 Job 名称。名称不能超过 52 个字符，最好同时满足 DNS Label 规则，避免追加后缀后超过 Job 的 63 字符限制。

## Cron 表达式

`schedule` 使用五个字段，不包含秒：

```text
# ┌───────────── 分钟（0-59）
# │ ┌───────────── 小时（0-23）
# │ │ ┌───────────── 每月第几日（1-31）
# │ │ │ ┌───────────── 月份（1-12）
# │ │ │ │ ┌───────────── 每周第几日（0-6，星期日为 0）
# │ │ │ │ │
# * * * * *
```

支持范围、列表和步长，例如 `0 2 * * *` 表示每天 02:00，`*/15 * * * *` 表示每 15 分钟。还支持 `@hourly`、`@daily`（或 `@midnight`）、`@weekly`、`@monthly` 和 `@yearly`（或 `@annually`）等宏。

Cron 的“每月第几日”和“每周第几日”字段同时受限时，只要其中一个匹配就可能触发，复杂表达式应先用可靠的 Cron 解析工具验证，并结合 `.spec.timeZone` 检查实际时刻。

## 调度时区

Kubernetes v1.27 起，`.spec.timeZone` 已稳定可用。应使用 IANA 时区名称，例如 `Etc/UTC` 或 `Asia/Shanghai`。未设置时，调度按 `kube-controller-manager` 的本地时区解释，并不保证是用户所在时区或固定 UTC。

不能在 `schedule` 中写 `TZ=` 或 `CRON_TZ=`；Kubernetes 会把这种表达式判为无效。时区数据库优先来自控制器所在系统，缺失时使用 Go 标准库内置数据库。

## 手动触发

需要验证 CronJob 的 Job 模板时，可以创建一次性 Job：

```bash
kubectl create job hello-manual-001 --from=cj/hello
kubectl logs job/hello-manual-001
```

手动 Job 不受 CronJob 的 `concurrencyPolicy` 和历史数量控制，需要单独设置或继承模板中的 TTL，并自行清理。

## 观察执行记录

```bash
kubectl describe cj hello
kubectl get job -l app.kubernetes.io/name=hello-cronjob \
  --sort-by=.metadata.creationTimestamp
kubectl get po -l batch.kubernetes.io/job-name=<job-name>
```

从 Kubernetes v1.32 起，CronJob 创建的 Job 带有 `batch.kubernetes.io/cronjob-scheduled-timestamp` 注解，值是原计划创建时刻的 RFC3339 时间。它可用于判断调度延迟、生成幂等键或对账：

```bash
kubectl get job <job-name> \
  -o jsonpath='{.metadata.annotations.batch\.kubernetes\.io/cronjob-scheduled-timestamp}'
```

## 非恰好一次

在控制器故障、网络异常或状态同步竞争下，同一计划时刻可能创建两个 Job，也可能没有创建。`startingDeadlineSeconds` 较大或未设置且并发策略为 `Allow` 时，控制器会尽力保证至少执行一次，但仍不提供恰好一次语义。

任务应使用业务主键、计划时间、事务或条件写入实现幂等，并能识别重复备份、重复通知和重复扣减等副作用。CronJob 的调度历史不能替代业务侧执行记录。
