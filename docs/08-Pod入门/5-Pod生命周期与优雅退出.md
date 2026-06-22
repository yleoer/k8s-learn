# Pod 生命周期与优雅退出

Pod 从提交 YAML 到正式接收流量，需要经过 API 写入、调度、镜像拉取、容器创建、探针检查和 Endpoint 更新等多个阶段。Pod 删除时不会立即终止容器，而是进入一个受控的终止流程。

## 启动过程

典型启动过程如下：

```text
提交 Pod
  -> APIServer 写入 etcd
  -> Scheduler 选择节点
  -> kubelet 监听到 Pod
  -> 创建 Pod 网络与存储
  -> 拉取镜像
  -> 启动 Init Container
  -> 启动普通容器
  -> 执行 postStart
  -> startupProbe 成功
  -> livenessProbe 与 readinessProbe 持续检查
  -> Pod Ready
  -> Endpoint 添加 Pod IP
```

`Running` 不等于可接流量。Pod 是否可以接收 Service 流量，主要取决于 `Ready` 条件是否通过。

启动阶段常见状态：

| 状态 | 常见原因 |
| --- | --- |
| `Pending` | 未完成调度、资源不足、PVC 未绑定、节点约束不满足 |
| `ContainerCreating` | 正在拉镜像、创建网络、挂载 volume |
| `Running 0/1` | 容器已运行，但 readinessProbe 未通过 |

## Init Container

Init Container 用于在普通容器启动前执行初始化任务。一个 Pod 可以定义多个 Init Container，它们会按照定义顺序依次执行；只有所有 Init Container 都成功完成后，普通容器才会启动。

下面示例先由 `init-page` 容器写入首页文件，再由 `nginx` 容器挂载同一个 `emptyDir` 卷并对外提供访问：

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: init-container-demo
spec:
  volumes:
    - name: web-content
      emptyDir: {}
  initContainers:
    - name: init-page
      image: busybox:1.36.1
      command:
        - /bin/sh
        - -c
        - echo "Hello from init container" > /work-dir/index.html
      volumeMounts:
        - name: web-content
          mountPath: /work-dir
  containers:
    - name: nginx
      image: nginx:stable-alpine
      ports:
        - containerPort: 80
      volumeMounts:
        - name: web-content
          mountPath: /usr/share/nginx/html
```

创建并查看 Pod：

```bash
kubectl create -f init-container-demo.yaml
kubectl get pod init-container-demo
kubectl describe pod init-container-demo
```

查看 Init Container 日志：

```bash
kubectl logs init-container-demo -c init-page
```

验证普通容器是否读取到初始化内容：

```bash
kubectl exec -it init-container-demo -c nginx -- cat /usr/share/nginx/html/index.html
```

Init Container 适合执行依赖检查、等待外部服务、准备配置文件或生成启动前所需数据。不适合承载长期运行任务，因为 Init Container 必须成功退出，Pod 才能继续启动普通容器。

## 退出过程

典型退出过程如下：

```text
删除 Pod
  -> Pod 进入 Terminating
  -> readiness 状态变为 False
  -> Endpoint 移除 Pod IP
  -> kubelet 执行 preStop
  -> kubelet 向容器主进程发送 SIGTERM
  -> 等待 terminationGracePeriodSeconds
  -> 容器正常退出，Pod 删除完成
  -> 超过宽限期仍未退出，发送 SIGKILL
```

删除 Pod：

```bash
kubectl delete pod <pod-name>
kubectl delete pod <pod-name> --grace-period=10
```

强制删除只适合异常清理，不适合作为常规发布方式：

```bash
kubectl delete pod <pod-name> --grace-period=0 --force
```

## PostStart

`postStart` 是容器创建后执行的生命周期钩子。

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: poststart-demo
spec:
  containers:
    - name: nginx
      image: nginx:stable-alpine
      lifecycle:
        postStart:
          exec:
            command:
              - /bin/sh
              - -c
              - echo "Hello from postStart" > /usr/share/nginx/html/index.html
```

postStart 不保证早于主进程执行，不能替代应用启动时必须依赖的初始化逻辑。复杂初始化更适合放到 Init Container 或镜像入口脚本中完成。

创建并验证 postStart 执行结果：

```bash
kubectl create -f poststart-demo.yaml
kubectl get pod poststart-demo
kubectl exec -it poststart-demo -- cat /usr/share/nginx/html/index.html
```

## PreStop 与宽限期

`preStop` 是容器终止前执行的钩子，常用于等待流量收敛、通知应用下线或执行清理动作。

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: prestop-demo
spec:
  terminationGracePeriodSeconds: 30
  containers:
    - name: nginx
      image: nginx:stable-alpine
      ports:
        - containerPort: 80
      lifecycle:
        preStop:
          exec:
            command:
              - /bin/sh
              - -c
              - echo "preStop hook is running, wait before exit..." && sleep 10
```

preStop 的执行时间包含在 `terminationGracePeriodSeconds` 之内。应用本身仍需正确处理 `SIGTERM`，停止接收新请求，等待存量请求完成后再退出。

创建 Pod 后删除，并观察 preStop 带来的退出等待：

```bash
kubectl create -f prestop-demo.yaml
kubectl get pod prestop-demo
time kubectl delete pod prestop-demo
```

:::details 输出示例

```bash
$ time kubectl delete po prestop-demo
pod "prestop-demo" deleted from default namespace
kubectl delete po prestop-demo  0.01s user 0.03s system 0% cpu 10.691 total
```

:::

由于 preStop 中执行了 `sleep 10`，Pod 会在 `Terminating` 状态停留一段时间。`terminationGracePeriodSeconds: 30` 表示 kubelet 最多给容器 30 秒完成 preStop 和进程退出；如果超过该时间仍未退出，容器会被强制终止。

## 修改终止宽限期

当应用需要更长时间完成请求处理、连接关闭或本地清理时，可以调大 `terminationGracePeriodSeconds`。下面示例将宽限期调整为 60 秒，并在 preStop 中等待 45 秒，用于模拟较长的下线收敛过程：

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: graceful-period-demo
spec:
  terminationGracePeriodSeconds: 60
  containers:
    - name: nginx
      image: nginx:stable-alpine
      ports:
        - containerPort: 80
      lifecycle:
        preStop:
          exec:
            command:
              - /bin/sh
              - -c
              - echo "wait for traffic draining..." && sleep 45
```

创建并删除 Pod：

```bash
kubectl create -f graceful-period-demo.yaml
kubectl get pod graceful-period-demo
time kubectl delete pod graceful-period-demo
```

:::details 输出示例

```bash
$ time kubectl delete po graceful-period-demo
pod "graceful-period-demo" deleted from default namespace
kubectl delete po graceful-period-demo  0.01s user 0.03s system 0% cpu 45.719 total
```

:::

删除过程中，Pod 会先进入 `Terminating`，preStop 执行约 45 秒后容器退出。由于宽限期为 60 秒，preStop 和 Nginx 退出仍处于允许范围内。如果将 `terminationGracePeriodSeconds` 设置得小于 preStop 执行时间，例如 10 秒，preStop 还未执行完成时就可能被 kubelet 强制结束。

## 优雅退出建议

可靠的优雅退出通常需要同时满足以下条件：
- readinessProbe 能准确反映 Pod 是否应接入流量
- preStop 给流量入口留出收敛时间
- terminationGracePeriodSeconds 覆盖最长请求的处理时间
- 应用正确处理 SIGTERM
- 发布前通过压测或演练验证
