# Pod 基本使用

本文只记录最小 Pod 的创建、查看、日志、进入容器和删除操作。多容器协作、镜像拉取策略、资源配置、生命周期和探针等细节放在第 08 章继续整理。

## 创建单容器 Pod

编写 `nginx-pod.yaml`：

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  containers:
    - name: nginx
      image: nginx:1.27
      ports:
        - containerPort: 80
```

创建 Pod：

```bash
kubectl apply -f nginx-pod.yaml
```

查看状态：

```bash
kubectl get pod
kubectl get pod nginx -o wide
kubectl describe pod nginx
```

查看日志：

```bash
kubectl logs nginx
```

进入容器：

```bash
kubectl exec -it nginx -- sh
```

删除 Pod：

```bash
kubectl delete -f nginx-pod.yaml
```

## 使用命令快速创建

也可以使用 `run` 快速创建：

```bash
kubectl run nginx --image=nginx:1.27
kubectl get pod nginx -o yaml
```

生成 YAML 但不提交：

```bash
kubectl run nginx --image=nginx:1.27 --dry-run=client -o yaml
```

临时验证可以用 `run` 快速创建；需要反复保留的资源统一写入 YAML。

## 常见问题

Pod 创建失败时，先按以下顺序检查：

```bash
kubectl get pod -o wide
kubectl describe pod <pod-name>
kubectl logs <pod-name>
kubectl get events --sort-by=.metadata.creationTimestamp
```

常见原因包括镜像地址错误、节点资源不足、命令启动失败、端口冲突、配置挂载失败等。这里只保留最小观察路径，具体字段和排查方法在第 08 章按 Pod 配置主题展开。
