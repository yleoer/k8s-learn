# 任务管理速查

本章记录 Job 与 CronJob 的创建、观察和清理命令。Job 管理一次性任务的完成状态，CronJob 按计划创建 Job；它们不提供业务层恰好一次处理语义。

## 关键对象与边界

| 对象 | 作用 | 不负责 |
| --- | --- | --- |
| Job | 维护任务完成条件 | 对副作用自动去重 |
| Indexed Job | 提供稳定索引分片 | 代替外部任务队列 |
| CronJob | 周期性创建 Job | 保证每个时刻恰好执行一次 |

## 命令速查

### 创建与观察

```bash
kubectl create -f hello-job.yaml
kubectl create -f hello-cronjob.yaml
kubectl get job
kubectl get cj
kubectl describe job <job-name>
kubectl describe cj <cronjob-name>
```

### 执行记录与手动验证

```bash
kubectl get po -l batch.kubernetes.io/job-name=<job-name>
kubectl logs job/<job-name>
kubectl get ev --sort-by=.metadata.creationTimestamp
kubectl create job hello-manual-001 --from=cj/hello
```

### 清理与暂停

```bash
kubectl delete job <job-name>
kubectl delete cj <cronjob-name>
kubectl patch cj <cronjob-name> -p '{"spec":{"suspend":true}}'
```

暂停 CronJob 只阻止后续调度，不会终止已创建的 Job；删除或中止正在执行的任务前，应先确认其幂等和恢复策略。

## 配置速查

| 配置 | 检查重点 |
| --- | --- |
| `backoffLimit` | 失败重试上限 |
| `parallelism` / `completions` | 并行度与完成数 |
| `concurrencyPolicy` | CronJob 重叠执行行为 |
| `startingDeadlineSeconds` | 错过计划时刻后的补偿窗口 |

## 排查索引

| 现象 | 优先检查 | 正文 |
| --- | --- | --- |
| Job 未完成 | 容器退出码、重试、activeDeadlineSeconds | [失败策略与自动清理](./3-失败策略与自动清理.md) |
| CronJob 未触发 | schedule、timeZone、suspend 与控制器事件 | [CronJob 调度](./4-CronJob调度.md) |
| 重复副作用 | 幂等键、计划时刻和业务事务 | [CronJob 策略与备份](./5-CronJob策略与备份.md) |

## 关联页面

- [Job 资源与状态](./1-Job资源与状态.md)
- [并行任务与完成策略](./2-并行任务与完成策略.md)

## 参考

- [Job](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)
