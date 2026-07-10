# kubectl 命令速查

本附录按工作负载章节中的操作场景整理 `kubectl` 命令。命令中的资源名沿用正文示例，实际使用时应替换为当前 Namespace 下的资源名称。

> [!NOTE]
> `deployment`、`statefulset`、`daemonset`、`replicaset` 和 `pod` 在 `kubectl` 中常可分别简写为 `deploy`、`sts`、`ds`、`rs` 和 `po`。本页优先使用完整资源名，正文中保留常见简写。

## 查看资源

查看本章涉及的控制器和 Pod：

```bash
kubectl get deployment,replicaset,statefulset,daemonset
kubectl get pod -o wide
kubectl get pod -A -o wide
```

按资源名称查看：

```bash
kubectl get deployment/nginx-deploy
kubectl get statefulset/web
kubectl get daemonset/node-nginx
```

按标签查看下层 Pod 或 ReplicaSet：

```bash
kubectl get replicaset -l app=nginx-deploy
kubectl get pod -l app=nginx-deploy -o wide
kubectl get pod -l app=nginx -o wide
kubectl get pod -l app=node-nginx -o wide
```

查看完整对象内容和事件：

```bash
kubectl get deployment/nginx-deploy -o yaml
kubectl get statefulset/web -o yaml
kubectl get daemonset/node-nginx -o yaml

kubectl describe deployment/nginx-deploy
kubectl describe statefulset/web
kubectl describe daemonset/node-nginx
kubectl describe pod <pod-name>
```

查看节点标签与节点详情：

```bash
kubectl get node --show-labels
kubectl describe node <node-name>
```

## 创建与应用

根据 YAML 创建或更新工作负载：

```bash
kubectl apply -f nginx-deploy.yaml
kubectl apply -f web-statefulset.yaml
kubectl apply -f node-nginx-daemonset.yaml
```

创建章节公共背景中的 ReplicaSet 示例：

```bash
kubectl create -f nginx-rs.yaml
kubectl get replicaset
kubectl get pod -l app=nginx-rs -o wide
```

生成 Deployment 模板：

```bash
kubectl create deployment nginx-deploy --image=nginx:1.31-alpine --dry-run=client -o yaml
```

创建临时调试 Pod：

```bash
kubectl run dns-test --image=busybox:1.38 --restart=Never -- sleep 3600
kubectl get pod dns-test
```

## Deployment 发布

更新镜像并观察发布状态：

```bash
kubectl set image deployment/nginx-update nginx=nginx:1.31-alpine
kubectl rollout status deployment/nginx-update
kubectl annotate deployment/nginx-update kubernetes.io/change-cause="update nginx image" --overwrite
```

查看发布历史：

```bash
kubectl rollout history deployment/nginx-update
kubectl rollout history deployment/nginx-update --revision=3
kubectl get replicaset -l app=nginx-update
```

回滚到上一版本或指定版本：

```bash
kubectl rollout undo deployment/nginx-update
kubectl rollout status deployment/nginx-update

kubectl rollout undo deployment/nginx-update --to-revision=2
kubectl rollout status deployment/nginx-update
```

暂停、合并修改并恢复发布：

```bash
kubectl rollout pause deployment/nginx-update
kubectl set image deployment/nginx-update nginx=nginx:1.31-alpine
kubectl set env deployment/nginx-update APP_ENV=prod
kubectl set resources deployment/nginx-update -c=nginx --requests=cpu=100m,memory=128Mi --limits=cpu=500m,memory=256Mi
kubectl rollout resume deployment/nginx-update
kubectl rollout status deployment/nginx-update
```

触发一次滚动重启：

```bash
kubectl rollout restart deployment/nginx-update
kubectl rollout status deployment/nginx-update
```

> [!NOTE]
> 使用 `kubernetes.io/change-cause` 记录变更说明时，正文采用先触发 Pod 模板变更并等待发布完成，再写入注解的顺序，避免覆盖旧 revision 的说明。

## 扩缩容

调整 Deployment 副本数：

```bash
kubectl scale deployment/nginx-scale --replicas=5
kubectl get pod -l app=nginx-scale -o wide

kubectl scale deployment/nginx-scale --replicas=2
kubectl get deployment/nginx-scale
```

使用当前副本数作为前置条件：

```bash
kubectl scale --current-replicas=3 deployment/nginx-scale --replicas=5
```

调整 StatefulSet 副本数并观察有序变化：

```bash
kubectl scale statefulset/web --replicas=5
kubectl get pod -l app=nginx -w

kubectl scale statefulset/web --replicas=2
kubectl get pod -l app=nginx -w
```

查看资源占用：

```bash
kubectl top node
kubectl top pod
```

> [!NOTE]
> `kubectl top` 依赖 Metrics Server。集群没有可用指标来源时，该命令无法返回 CPU 和内存用量。

## StatefulSet 操作

查看 StatefulSet、Headless Service、Pod 和 PVC：

```bash
kubectl get statefulset/web
kubectl get service/nginx
kubectl get pod -l app=nginx -o wide
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
kubectl set image statefulset/web nginx=nginx:1.31-alpine
kubectl rollout status statefulset/web
kubectl rollout history statefulset/web
```

分段更新：

```bash
kubectl patch statefulset/partition-web -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":2}}}}'
kubectl patch statefulset/partition-web -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":1}}}}'
kubectl patch statefulset/partition-web -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":0}}}}'
```

查看分段更新后的镜像分布：

```bash
kubectl get pod -l app=partition-web -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
```

OnDelete 策略下手动删除 Pod 触发重建：

```bash
kubectl set image statefulset/ondelete-web nginx=nginx:1.31-alpine
kubectl delete pod ondelete-web-2
kubectl get pod ondelete-web-2 -w
```

回滚 StatefulSet：

```bash
kubectl rollout undo statefulset/web
kubectl rollout status statefulset/web

kubectl rollout undo statefulset/web --to-revision=2
kubectl rollout status statefulset/web
```

## DaemonSet 操作

创建并查看 DaemonSet：

```bash
kubectl apply -f node-nginx-daemonset.yaml
kubectl get daemonset/node-nginx
kubectl get pod -l app=node-nginx -o wide
```

更新镜像并观察发布：

```bash
kubectl set image daemonset/node-nginx nginx=nginx:1.31-alpine
kubectl rollout status daemonset/node-nginx
kubectl rollout history daemonset/node-nginx
```

回滚 DaemonSet：

```bash
kubectl rollout undo daemonset/node-nginx
kubectl rollout status daemonset/node-nginx

kubectl rollout undo daemonset/node-nginx --to-revision=2
kubectl rollout status daemonset/node-nginx
```

OnDelete 策略下手动删除 Pod 触发重建：

```bash
kubectl set image daemonset/ondelete-node-nginx nginx=nginx:1.31-alpine
kubectl delete pod <daemonset-pod-name>
kubectl get pod -l app=ondelete-node-nginx -o wide
```

通过节点标签控制调度范围：

```bash
kubectl label node <node-name> node-role.example.com/logging=true
kubectl get daemonset/logging-agent
kubectl get pod -l app=logging-agent -o wide

kubectl label node <node-name> node-role.example.com/logging-
```

查看污点和 DaemonSet 排查信息：

```bash
kubectl describe node <node-name> | grep -i taints
kubectl get daemonset/node-nginx -o wide
kubectl describe daemonset/node-nginx
kubectl describe pod <pod-name>
```

## Pod 排查

查看 Pod 状态、事件和日志：

```bash
kubectl get pod <pod-name> -o wide
kubectl describe pod <pod-name>
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
kubectl wait --for=condition=available deployment/nginx-deploy --timeout=120s
kubectl wait --for=condition=Ready pod/web-0 --timeout=60s
kubectl wait --for=delete pod/ondelete-web-2 --timeout=60s
```

## 删除与清理

删除 Deployment、ReplicaSet 和 DaemonSet：

```bash
kubectl delete deployment/nginx-deploy
kubectl delete replicaset/nginx-rs
kubectl delete daemonset/node-nginx
```

删除 StatefulSet、Service 和临时 Pod：

```bash
kubectl delete statefulset/web
kubectl delete service/nginx
kubectl delete pod dns-test
```

保留 Pod 删除 StatefulSet：

```bash
kubectl delete statefulset/web --cascade=orphan
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

- [Command line tool kubectl](https://kubernetes.io/docs/reference/kubectl/)
- [kubectl Quick Reference](https://kubernetes.io/docs/reference/kubectl/quick-reference/)
- [kubectl reference](https://kubernetes.io/docs/reference/kubectl/generated/)
- [kubectl apply](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_apply/)
- [kubectl get](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_get/)
- [kubectl describe](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_describe/)
- [kubectl rollout](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_rollout/)
- [kubectl scale](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_scale/)
- [kubectl set](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_set/)
- [kubectl patch](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_patch/)
- [kubectl label](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_label/)
- [kubectl logs](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_logs/)
- [kubectl exec](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_exec/)
- [kubectl top](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_top/)
- [kubectl wait](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/)
