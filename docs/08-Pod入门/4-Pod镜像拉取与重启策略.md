# Pod 镜像拉取与重启策略

Pod 通过 `imagePullPolicy` 指定镜像下载策略，通过 `restartPolicy` 定义容器退出后的重启行为。二者分别控制容器启动前和退出后的处理逻辑。

## 镜像下载策略

| 策略             | 说明             | 常见场景                    |
|----------------|----------------|-------------------------|
| `Always`       | 每次启动容器都检查并拉取镜像 | 使用 `latest` 或测试环境强制更新镜像 |
| `IfNotPresent` | 本地不存在镜像时才拉取    | 固定版本镜像、离线环境             |
| `Never`        | 从不拉取，只使用本地镜像   | 完全离线或调试本地镜像             |

示例：

```yaml [image-policy-demo.yaml]
apiVersion: v1
kind: Pod
metadata:
  name: image-policy-demo
spec:
  containers:
    - name: nginx
      image: nginx:stable-alpine
      imagePullPolicy: IfNotPresent
```

默认规则：

| 镜像写法                    | 默认策略           |
|-------------------------|----------------|
| `nginx`                 | `Always`       |
| `nginx:latest`          | `Always`       |
| `nginx:stable-alpine`   | `IfNotPresent` |
| `nginx@sha256:<digest>` | `IfNotPresent` |

`imagePullPolicy` 的默认值在对象创建时确定，之后修改镜像 tag 不会自动改变已有对象的该字段。生产环境建议使用固定 tag 或 digest，避免使用可变的 `latest` 标签。

## 私有仓库认证

私有仓库需要配置 `imagePullSecrets`：

```yaml [private-image-demo.yaml]
apiVersion: v1
kind: Pod
metadata:
  name: private-image-demo
spec:
  imagePullSecrets:
    - name: registry-secret
  containers:
    - name: app
      image: registry.example.com/project/app:v1.0.0
```

创建 Secret：

```bash
kubectl create secret docker-registry registry-secret \
  --docker-server=registry.example.com \
  --docker-username=<username> \
  --docker-password=<password> \
  --docker-email=<email>
```

## 节点有镜像仍拉取失败

常见原因包括：

- `imagePullPolicy` 配置为 `Always`
- 镜像只导入到了某个节点，Pod 被调度到了其他节点
- containerd 镜像导入到了错误命名空间
- Pod 中镜像名称和本地镜像名称不完全一致
- 私有仓库认证失败

containerd 离线导入镜像时注意使用 Kubernetes 命名空间：

```bash
ctr -n k8s.io images import app.tar
ctr -n k8s.io images list
crictl images
```

排查顺序：

```bash
kubectl describe pod <pod-name>
kubectl get pod <pod-name> -o wide
crictl images
```

优先查看 Events 中的真实错误信息，例如 `unauthorized`、`not found`、`connection refused`。

## 重启策略

Pod 通过 `spec.restartPolicy` 定义容器退出后的处理方式。

| 策略          | 含义             | 常见场景       |
|-------------|----------------|------------|
| `Always`    | 容器退出后总是重启      | 长期运行服务，默认值 |
| `OnFailure` | 容器非 0 状态码退出时重启 | 一次性任务、Job  |
| `Never`     | 容器退出后不重启       | 调试、一次性命令   |

示例：

```yaml [restart-demo.yaml]
apiVersion: v1
kind: Pod
metadata:
  name: restart-demo
spec:
  restartPolicy: Always
  containers:
    - name: demo
      image: busybox:1.36.1
      command:
        - sh
        - -c
      args:
        - echo start; sleep 5; exit 1
```

查看重启次数和上一次日志：

```bash
kubectl get pod restart-demo
kubectl logs restart-demo
kubectl logs restart-demo --previous
kubectl describe pod restart-demo
```

::: details 输出示例

```bash
$ kubectl get po restart-demo
NAME           READY   STATUS   RESTARTS      AGE
restart-demo   0/1     Error    3 (63s ago)   92s

$ kubectl logs restart-demo
start
```

:::

普通 Pod 被删除后不会自动重建；由 Deployment、Job 等控制器创建的 Pod 才会被控制器继续管理。
