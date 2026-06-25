# Deployment 更新与回滚

Deployment 的更新由 Pod 模板变化触发。常见触发点包括镜像版本、环境变量、启动命令、资源限制、探针以及模板的标签和注解等字段。

仅修改 `spec.replicas` 不会触发新版本发布，因为副本数不属于 Pod 模板。

## 更新镜像

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

### 更新未触发的常见原因

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

## 查看历史版本

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

## 版本回滚

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

## 暂停和恢复

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

## 历史版本保留

`revisionHistoryLimit` 用于控制 Deployment 保留多少个旧版本：

```yaml
spec:
  revisionHistoryLimit: 5
```

常见取值为 5 到 10。版本保留数量需要结合发布频率、回滚要求和集群规模确定。不要把 Deployment 历史版本当作唯一回滚手段，可靠的回滚还应包括 Git 中的 YAML、不可变镜像 tag、配置变更记录和数据库变更预案。
