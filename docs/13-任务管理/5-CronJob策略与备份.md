# CronJob 策略与备份

CronJob 的并发策略决定同一 CronJob 的多个 Job 是否重叠，启动截止时间决定错过计划后是否补建，历史上限决定已结束 Job 的保留数量。这些字段不改变 Job 内部的失败重试语义。

## 并发策略

| `concurrencyPolicy` | 行为                              |
|---------------------|---------------------------------|
| `Allow`             | 允许同一 CronJob 的多个 Job 重叠运行，也是默认值 |
| `Forbid`            | 上一次 Job 未结束时跳过本次创建，该次计为错过调度     |
| `Replace`           | 到达新计划时，终止旧 Job 并创建新 Job         |

并发策略只比较同一个 CronJob 创建的 Job，不会阻止其他 CronJob 或手动 Job 同时访问相同数据库、PVC 或外部 API。需要跨任务互斥时，应由应用锁、数据库租约或专用协调服务实现。

`Replace` 会中断旧任务，不等于等待它优雅完成。备份、迁移和批量写入通常更适合 `Forbid`，并配合合理截止时间，避免两个实例同时修改同一目标。

## 错过调度与截止时间

`startingDeadlineSeconds` 表示计划时刻过去多少秒后不再补建该次 Job。未设置时没有单次启动截止时间。

CronJob 控制器通常每 10 秒检查一次，设置小于 10 秒可能导致任务无法被调度。控制器会统计错过的计划时刻；超过 100 次时不会补建并记录 `Too many missed start time`，后续正常计划仍可继续。

设置 `startingDeadlineSeconds` 后，错过次数只在该时间窗口内计算。例如每分钟任务设置 200 秒时，控制器恢复后只考虑最近约 200 秒内的计划，而不是从最后一次成功调度一直追溯。

`Forbid` 阻止重叠时，该计划会计为错过；旧 Job 结束后，如果对应计划仍处于 `startingDeadlineSeconds` 窗口内，控制器仍可能补建一次。任务对“跳过”和“延迟补建”都应保持幂等，不能只依赖并发策略推断执行次数。

## 暂停与恢复

```bash
kubectl patch cronjob hello --type merge -p '{"spec":{"suspend":true}}'
kubectl get cronjob hello
kubectl patch cronjob hello --type merge -p '{"spec":{"suspend":false}}'
```

暂停只阻止后续 Job 创建，不影响已经运行的 Job。暂停期间的计划时刻会计为错过；恢复时如果没有设置启动截止时间，错过的执行可能被立即补建，因此长期暂停前应设置合适的 `startingDeadlineSeconds` 或在恢复前调整计划。

## 历史与 TTL

`successfulJobsHistoryLimit` 默认保留 3 个成功 Job，`failedJobsHistoryLimit` 默认保留 1 个失败 Job，设置为 `0` 表示不保留对应历史。Job 模板中的 `ttlSecondsAfterFinished` 还可以按时间清理，两种机制同时存在时，先满足的条件会触发删除。

任务日志应由集群日志系统独立采集。依赖 Job 和 Pod 长期保留日志会持续占用 API Server 和 etcd 空间，也无法覆盖节点日志丢失场景。

## MySQL 定时备份

下面的 CronJob 每天 02:00 连接 `mysql.default.svc.cluster.local`，把逻辑备份写入 NFS CSI 动态 PVC，并删除保存时间达到 7 天的 `.sql` 文件。

执行前需要满足：

- 已按 [NFS 与 CSI 动态存储](/12-存储管理/4-NFS与CSI动态存储) 创建 `nfs-csi` StorageClass。
- 当前命名空间存在 `mysql-backup-credentials` Secret，包含 `backup.cnf` 键；创建与保护方式见 [Secret 资源](/11-配置管理/3-Secret资源)。
- MySQL Service、账号权限、网络策略和服务端 TLS 配置允许备份 Pod 访问。

在仓库外准备 MySQL 客户端配置；实际启用 TLS 时，还应按服务端证书配置 `ssl-mode=VERIFY_IDENTITY`、`ssl-ca` 等选项：

```ini [backup.cnf]
[client]
user="<database-backup-user>"
password="<database-backup-password>"
```

从文件创建 Secret，避免把凭据直接放入命令参数：

```bash
kubectl create secret generic mysql-backup-credentials \
  --from-file=backup.cnf
```

```yaml [mysql-backup-cronjob.yaml]
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-backup-data
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: nfs-csi
  resources:
    requests:
      storage: 20Gi
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: mysql-backup
spec:
  schedule: "0 2 * * *"
  timeZone: Asia/Shanghai
  concurrencyPolicy: Forbid
  startingDeadlineSeconds: 3600
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    metadata:
      labels:
        app.kubernetes.io/name: mysql-backup
    spec:
      backoffLimit: 2
      activeDeadlineSeconds: 1800
      ttlSecondsAfterFinished: 604800
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: backup
              image: mysql:8.4
              command:
                - sh
                - -ec
                - |
                  umask 077
                  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
                  target="/backup/mysql-${stamp}.sql"
                  temporary="${target}.tmp"
                  trap 'rm -f "${temporary}"' EXIT
                  mysqldump \
                    --defaults-extra-file=/run/secrets/mysql/backup.cnf \
                    --host=mysql.default.svc.cluster.local \
                    --single-transaction \
                    --routines \
                    --events \
                    --all-databases > "${temporary}"
                  mv "${temporary}" "${target}"
                  trap - EXIT
                  find /backup -type f -name 'mysql-*.sql' -mtime +6 -delete
              volumeMounts:
                - name: backup
                  mountPath: /backup
                - name: mysql-client-config
                  mountPath: /run/secrets/mysql
                  readOnly: true
          volumes:
            - name: backup
              persistentVolumeClaim:
                claimName: mysql-backup-data
            - name: mysql-client-config
              secret:
                secretName: mysql-backup-credentials
                defaultMode: 0400
                items:
                  - key: backup.cnf
                    path: backup.cnf
```

```bash
kubectl create -f mysql-backup-cronjob.yaml
kubectl get cronjob mysql-backup
kubectl create job mysql-backup-manual-001 --from=cronjob/mysql-backup
kubectl logs job/mysql-backup-manual-001
```

Secret 以只读文件挂载，避免凭据出现在环境变量和 `mysqldump` 命令参数中；应用仍不应打印该文件。`--single-transaction` 可为支持事务的 InnoDB 表提供一致性视图，但不能保证 MyISAM、DDL 并发或所有外部对象的一致性。备份账号应只拥有完成备份所需的最小权限，并按实际需求决定是否包含存储过程、事件和全部数据库。

> [!CAUTION]
> 把备份写到与数据库相同故障域的 NFS 只能防止部分逻辑误操作，不能替代异地备份。生产方案还需要加密、校验、离线或异地复制、保留锁定、容量监控和定期恢复演练。NFS PVC 的 `20Gi` 声明也不自动形成服务端目录配额。

## 定期重启边界

不应把 CronJob 定期执行 `kubectl rollout restart` 作为服务稳定性机制。该做法需要向任务授予修改工作负载的 RBAC 权限，会掩盖内存泄漏、连接失效或探针配置问题，并可能与发布控制器发生竞争。

进程故障应通过 `livenessProbe`、`startupProbe` 和应用自身恢复处理；配置或镜像变更应由声明式发布流程触发滚动更新。只有经过审计的临时运维场景才考虑调度控制面操作，并使用专用 ServiceAccount、最小资源范围 RBAC、变更记录和失败告警。

## 排查顺序

```bash
kubectl describe cronjob <cronjob-name>
kubectl get job -l app.kubernetes.io/name=<job-template-label> \
  --sort-by=.metadata.creationTimestamp
kubectl describe job <job-name>
kubectl get pod -l batch.kubernetes.io/job-name=<job-name>
kubectl logs job/<job-name>
kubectl get events --sort-by=.metadata.creationTimestamp
```

重点核对 `LAST SCHEDULE`、`SUSPEND`、活动 Job、时区、启动截止时间、并发策略、错过次数，以及 Job 内部的退出码、退避、截止时间和存储或 Secret 依赖。
