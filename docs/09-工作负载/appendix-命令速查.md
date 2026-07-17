# kubectl 命令速查

本附录按工作负载章节中的操作场景整理 `kubectl` 命令。命令中的资源名沿用正文示例，实际使用时应替换为当前 Namespace 下的资源名称。

> [!NOTE]
> `deployment`、`statefulset`、`daemonset`、`replicaset` 和 `pod` 在 `kubectl` 中常可分别简写为 `deploy`、`sts`、`ds`、`rs` 和 `po`。本页优先使用完整资源名，正文中保留常见简写。

## 查看资源

查看本章涉及的控制器和 Pod：

```bash
kubectl get deploy,replicaset,statefulset,daemonset
kubectl get po -o wide
kubectl get po -A -o wide
```

按资源名称查看：

```bash
kubectl get deploy/nginx-deploy
kubectl get sts/web
kubectl get ds/node-nginx
```

按标签查看下层 Pod 或 ReplicaSet：

```bash
kubectl get rs -l app=nginx-deploy
kubectl get po -l app=nginx-deploy -o wide
kubectl get po -l app=nginx -o wide
kubectl get po -l app=node-nginx -o wide
```

查看完整对象内容和事件：

```bash
kubectl get deploy/nginx-deploy -o yaml
kubectl get sts/web -o yaml
kubectl get ds/node-nginx -o yaml

kubectl describe deploy/nginx-deploy
kubectl describe sts/web
kubectl describe ds/node-nginx
kubectl describe po <pod-name>
```

查看节点标签与节点详情：

```bash
kubectl get no --show-labels
kubectl describe no <node-name>
```

## 创建资源

完整清单分别见 [Deployment 最小示例](./1-Deployment.md#最小示例)中的 `nginx-deploy.yaml`、[StatefulSet 最小示例](./2-StatefulSet.md#最小示例)中的 `web-statefulset.yaml` 和 [DaemonSet 最小示例](./3-DaemonSet.md#最小示例)中的 `node-nginx-daemonset.yaml`。首次创建工作负载：

```bash
kubectl create -f nginx-deploy.yaml
kubectl create -f web-statefulset.yaml
kubectl create -f node-nginx-daemonset.yaml
```

复用[副本控制器](./index.md#副本控制器)中的完整 `nginx-rs.yaml` 创建 ReplicaSet：

```bash
kubectl create -f nginx-rs.yaml
kubectl get rs
kubectl get po -l app=nginx-rs -o wide
```

生成 Deployment 模板：

```bash
kubectl create deploy nginx-deploy --image=nginx:1.31-alpine --dry-run=client -o yaml
```

创建临时调试 Pod：

```bash
kubectl run dns-test --image=busybox:1.38 --restart=Never -- sleep 3600
kubectl get po dns-test
```

## Deployment 发布

更新镜像并观察发布状态：

```bash
kubectl set image deploy/nginx-update nginx=nginx:1.31-alpine
kubectl rollout status deploy/nginx-update
kubectl annotate deploy/nginx-update kubernetes.io/change-cause="update nginx image" --overwrite
```

查看发布历史：

```bash
kubectl rollout history deploy/nginx-update
kubectl rollout history deploy/nginx-update --revision=3
kubectl get rs -l app=nginx-update
```

回滚到上一版本或指定版本：

```bash
kubectl rollout undo deploy/nginx-update
kubectl rollout status deploy/nginx-update

kubectl rollout undo deploy/nginx-update --to-revision=2
kubectl rollout status deploy/nginx-update
```

暂停、合并修改并恢复发布：

```bash
kubectl rollout pause deploy/nginx-update
kubectl set image deploy/nginx-update nginx=nginx:1.31-alpine
kubectl set env deploy/nginx-update APP_ENV=prod
kubectl set resources deploy/nginx-update -c=nginx --requests=cpu=100m,memory=128Mi --limits=cpu=500m,memory=256Mi
kubectl rollout resume deploy/nginx-update
kubectl rollout status deploy/nginx-update
```

触发一次滚动重启：

```bash
kubectl rollout restart deploy/nginx-update
kubectl rollout status deploy/nginx-update
```

> [!NOTE]
> 使用 `kubernetes.io/change-cause` 记录变更说明时，正文采用先触发 Pod 模板变更并等待发布完成，再写入注解的顺序，避免覆盖旧 revision 的说明。

## 扩缩容

调整 Deployment 副本数：

```bash
kubectl scale deploy/nginx-deploy --replicas=5
kubectl get po -l app=nginx-deploy -o wide

kubectl scale deploy/nginx-deploy --replicas=2
kubectl get deploy/nginx-deploy
```

使用当前副本数作为前置条件：

```bash
kubectl scale --current-replicas=3 deploy/nginx-deploy --replicas=5
```

调整 StatefulSet 副本数并观察有序变化：

```bash
kubectl scale sts/web --replicas=5
kubectl get po -l app=nginx -w

kubectl scale sts/web --replicas=2
kubectl get po -l app=nginx -w
```

查看资源占用：

```bash
kubectl top no
kubectl top po
```

> [!NOTE]
> `kubectl top` 依赖 Metrics Server。集群没有可用指标来源时，该命令无法返回 CPU 和内存用量。

## StatefulSet 操作

查看 StatefulSet、Headless Service、Pod 和 PVC：

```bash
kubectl get sts/web
kubectl get svc/nginx
kubectl get po -l app=nginx -o wide
kubectl get pvc
```

验证固定 DNS 名称和内部访问：

```bash
kubectl exec -it dns-test -- nslookup web-0.nginx.default.svc.cluster.local
kubectl exec -it dns-test -- nslookup web-1.nginx.default.svc.cluster.local
kubectl exec -it dns-test -- wget -qO- web-0.nginx
```

更新镜像并查看发布状态：

```bash
kubectl set image sts/web nginx=nginx:1.31-alpine
kubectl rollout status sts/web
kubectl rollout history sts/web
```

分段更新：

```bash
kubectl patch sts/partition-web -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":2}}}}'
kubectl patch sts/partition-web -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":1}}}}'
kubectl patch sts/partition-web -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":0}}}}'
```

查看分段更新后的镜像分布：

```bash
kubectl get po -l app=partition-web -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
```

OnDelete 策略下手动删除 Pod 触发重建：

```bash
kubectl set image sts/ondelete-web nginx=nginx:1.31-alpine
kubectl delete po ondelete-web-2
kubectl get po ondelete-web-2 -w
```

回滚 StatefulSet：

```bash
kubectl rollout undo sts/web
kubectl rollout status sts/web

kubectl rollout undo sts/web --to-revision=2
kubectl rollout status sts/web
```

## DaemonSet 操作

复用前文[创建资源](#创建资源)中已经创建的 DaemonSet，查看资源状态：

```bash
kubectl get ds/node-nginx
kubectl get po -l app=node-nginx -o wide
```

更新镜像并观察发布：

```bash
kubectl set image ds/node-nginx nginx=nginx:1.31-alpine
kubectl rollout status ds/node-nginx
kubectl rollout history ds/node-nginx
```

回滚 DaemonSet：

```bash
kubectl rollout undo ds/node-nginx
kubectl rollout status ds/node-nginx

kubectl rollout undo ds/node-nginx --to-revision=2
kubectl rollout status ds/node-nginx
```

OnDelete 策略下手动删除 Pod 触发重建：

```bash
kubectl set image ds/ondelete-node-nginx nginx=nginx:1.31-alpine
kubectl delete po <daemonset-pod-name>
kubectl get po -l app=ondelete-node-nginx -o wide
```

通过节点标签控制调度范围：

```bash
kubectl label no <node-name> node-role.example.com/logging=true
kubectl get ds/logging-agent
kubectl get po -l app=logging-agent -o wide

kubectl label no <node-name> node-role.example.com/logging-
```

查看污点和 DaemonSet 排查信息：

```bash
kubectl describe no <node-name> | grep -i taints
kubectl get ds/node-nginx -o wide
kubectl describe ds/node-nginx
kubectl describe po <pod-name>
```

## Pod 排查

查看 Pod 状态、事件和日志：

```bash
kubectl get po <pod-name> -o wide
kubectl describe po <pod-name>
kubectl logs <pod-name>
kubectl logs <pod-name> -c <container-name>
kubectl logs -f -l app=node-nginx --all-containers
```

进入容器执行命令：

```bash
kubectl exec -it <pod-name> -- sh
kubectl exec -it <pod-name> -c <container-name> -- sh
```

等待资源达到条件：

```bash
kubectl wait --for=condition=available deploy/nginx-deploy --timeout=120s
kubectl wait --for=condition=Ready po/web-0 --timeout=60s
kubectl wait --for=delete po/ondelete-web-2 --timeout=60s
```

## 删除与清理

删除 Deployment、ReplicaSet 和 DaemonSet：

```bash
kubectl delete deploy/nginx-deploy
kubectl delete rs/nginx-rs
kubectl delete ds/node-nginx
```

删除 StatefulSet、Service 和临时 Pod：

```bash
kubectl delete sts/web
kubectl delete svc/nginx
kubectl delete po dns-test
```

保留 Pod 删除 StatefulSet：

```bash
kubectl delete sts/web --cascade=orphan
```

删除 PVC：

```bash
kubectl get pvc
kubectl delete pvc data-web-2
```

> [!CAUTION]
> 删除 PVC 可能导致对应持久化数据不可恢复。执行清理前应确认数据已备份或不再需要。

## 参考

本文命令参考以下 Kubernetes 英文文档：

- [kubectl 命令行工具](https://kubernetes.io/docs/reference/kubectl/)
- [kubectl 命令速查](https://kubernetes.io/docs/reference/kubectl/quick-reference/)
- [kubectl 命令参考](https://kubernetes.io/docs/reference/kubectl/generated/)
- [kubectl apply 命令](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_apply/)
- [kubectl get 命令](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_get/)
- [kubectl describe 命令](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_describe/)
- [kubectl rollout 命令](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_rollout/)
- [kubectl scale 命令](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_scale/)
- [kubectl set 命令](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_set/)
- [kubectl patch 命令](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_patch/)
- [kubectl label 命令](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_label/)
- [kubectl logs 命令](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_logs/)
- [kubectl exec 命令](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_exec/)
- [kubectl top 命令](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_top/)
- [kubectl wait 命令](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/)
