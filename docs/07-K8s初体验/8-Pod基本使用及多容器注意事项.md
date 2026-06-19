# Pod 基本使用及多容器注意事项

本节先通过 YAML 创建一个基础 Pod，演示查看、进入容器、查看日志和删除等操作，再说明多容器 Pod 的常见注意事项。

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
      image: nginx:1.25
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
kubectl run nginx --image=nginx:1.25
kubectl get pod nginx -o yaml
```

生成 YAML 但不提交：

```bash
kubectl run nginx --image=nginx:1.25 --dry-run=client -o yaml
```

学习阶段可以用 `run` 快速验证；正式管理资源时，建议使用 YAML。

## 创建多容器 Pod

多容器 Pod 示例：

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: multi-container-demo
  labels:
    app: multi-demo
spec:
  containers:
    - name: app
      image: nginx:1.25
      ports:
        - containerPort: 80
    - name: sidecar
      image: busybox:1.36
      command:
        - sh
        - -c
        - while true; do echo sidecar running; sleep 10; done
```

创建并查看：

```bash
kubectl apply -f multi-container-demo.yaml
kubectl get pod multi-container-demo
```

查看指定容器日志：

```bash
kubectl logs multi-container-demo -c app
kubectl logs multi-container-demo -c sidecar
```

进入指定容器：

```bash
kubectl exec -it multi-container-demo -c sidecar -- sh
```

## 多容器注意事项

多容器 Pod 适合容器之间强依赖、强协作的场景。使用时要注意：

- 同一个 Pod 内的容器共享端口空间，不能监听相同端口
- 不指定 `-c` 时，日志查看和 exec 默认作用于第一个容器
- 一个容器异常退出可能导致 Pod 状态变为异常
- Pod 的资源用量是各容器之和，需要为每个容器分别设置 requests 和 limits
- 不要把无关服务放入同一个 Pod

多容器 Pod 的关键判断标准是：这些容器是否必须一起调度、一起运行、一起销毁。

## 镜像拉取策略

Pod 中常见镜像字段如下：

```yaml
spec:
  containers:
    - name: nginx
      image: nginx:1.25
      imagePullPolicy: IfNotPresent
```

常见策略：

| 策略 | 含义 |
| --- | --- |
| `Always` | 每次启动都尝试拉取镜像 |
| `IfNotPresent` | 本地不存在镜像时才拉取 |
| `Never` | 只使用本地镜像，不拉取 |

使用 `latest` 标签时，默认拉取策略会变为 `Always`，每次启动都会尝试拉取。生产环境建议使用明确的版本标签，避免镜像内容不可控。

## 初学常见问题

Pod 创建失败时，先按以下顺序检查：

```bash
kubectl get pod -o wide
kubectl describe pod <pod-name>
kubectl logs <pod-name>
kubectl get events --sort-by=.metadata.creationTimestamp
```

常见原因包括镜像地址错误、节点资源不足、命令启动失败、端口冲突、配置挂载失败等。
