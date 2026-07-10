# Pod 生命周期与优雅退出

Pod 从提交 YAML 到正式接收流量，需要经过 API 写入、调度、镜像拉取、容器创建和探针检查等多个阶段。Pod 被 Service selector 匹配时，Ready 状态还会影响对应 EndpointSlice 中的端点状态。Pod 删除时不会立即终止容器，而是进入一个受控的终止流程。

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
  -> 执行容器级 postStart
  -> startupProbe 成功
  -> livenessProbe 与 readinessProbe 持续检查
  -> Pod Ready
  -> 匹配 Service 时更新 EndpointSlice
```

`Running` 不等于可接流量。Pod 是否可以接收 Service 流量，主要取决于 `Ready` 条件是否通过。

启动阶段常见状态：

| 状态                  | 常见原因                       |
|---------------------|----------------------------|
| `Pending`           | 未完成调度、资源不足、PVC 未绑定、节点约束不满足 |
| `ContainerCreating` | 正在拉镜像、创建网络、挂载 volume       |
| `Running 0/1`       | 容器已运行，但 readinessProbe 未通过 |

## Init Container

Init Container 用于在普通容器启动前执行初始化任务。一个 Pod 可以定义多个 Init Container，它们会按照定义顺序依次执行；只有所有 Init Container 都成功完成后，普通容器才会启动。

下面示例先由 `init-page` 容器写入首页文件，再由 `nginx` 容器挂载同一个 `emptyDir` 卷并对外提供访问：

```yaml{9-18} [init-container-demo.yaml]
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
      image: busybox:1.38
      command:
        - /bin/sh
        - -c
        - echo "Hello from init container" > /work-dir/index.html
      volumeMounts:
        - name: web-content
          mountPath: /work-dir
  containers:
    - name: nginx
      image: nginx:1.31-alpine
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

Init Container 适合执行依赖检查、等待外部服务、准备配置文件或生成启动前所需数据。不适合承载长期运行任务，因为 Init Container 必须成功退出，Pod 才能继续启动普通容器；需要与主容器同生命周期运行的辅助进程，应使用容器级 `restartPolicy: Always` 的 Sidecar 容器，见 [Sidecar 容器](./7-Sidecar容器.md)。

## 退出过程

典型退出过程可概括如下。实际处理存在并发关系，不应理解为严格线性顺序：

```text
删除 Pod
  -> APIServer 标记 Pod 进入 Terminating 并记录宽限期
  -> 控制面逐步将该 Pod 从 Service 可用后端中摘除
  -> kubelet 执行容器级 preStop
  -> kubelet 通过运行时向容器主进程发送 SIGTERM 或镜像定义的 STOPSIGNAL
  -> 在剩余 terminationGracePeriodSeconds 内等待进程退出
  -> 容器正常退出，Pod 删除完成
  -> 超过宽限期仍未退出，发送 SIGKILL
```

删除 Pod：

```bash
kubectl delete pod <pod-name>
kubectl delete pod <pod-name> --grace-period=10
```

`--grace-period=10` 表示本次删除请求给 Pod 留 10 秒优雅终止时间。Pod 进入 `Terminating` 后，kubelet 会在这个时间窗口内执行 `preStop`、发送 `SIGTERM` 或镜像定义的 `STOPSIGNAL`，并等待容器进程自行退出；如果到期后仍有进程未退出，后续会被强制终止。未显式指定 `--grace-period` 时，删除通常使用 Pod 的 `terminationGracePeriodSeconds`；该字段未配置时默认 30 秒。

删除命令中的 `--grace-period` 适合临时缩短本次删除等待时间，不应作为延长应用退出时间的主要方式。需要更长的优雅退出窗口时，应在 Pod YAML 中调整 `terminationGracePeriodSeconds`。`--grace-period=0` 只能和 `--force` 一起用于强制删除。

强制删除只适合异常清理，不适合作为常规发布方式：

```bash
kubectl delete pod <pod-name> --grace-period=0 --force
```

## PostStart

`postStart` 是容器创建后执行的容器级生命周期钩子。

```yaml{9-15} [poststart-demo.yaml]
apiVersion: v1
kind: Pod
metadata:
  name: poststart-demo
spec:
  containers:
    - name: nginx
      image: nginx:1.31-alpine
      lifecycle:
        postStart:
          exec:
            command:
              - /bin/sh
              - -c
              - echo "Hello from postStart" > /usr/share/nginx/html/index.html
```

postStart 与容器主进程启动过程关联，但不保证早于主进程执行，不能替代应用启动时必须依赖的初始化逻辑。复杂初始化更适合放到 Init Container 或镜像入口脚本中完成。

创建并验证 postStart 执行结果：

```bash
kubectl create -f poststart-demo.yaml
kubectl get pod poststart-demo
kubectl exec -it poststart-demo -- cat /usr/share/nginx/html/index.html
```

## PreStop 与宽限期

`preStop` 是容器终止前执行的容器级生命周期钩子，常用于等待流量收敛、通知应用下线或执行清理动作。

```yaml{6,12-18} [prestop-demo.yaml]
apiVersion: v1
kind: Pod
metadata:
  name: prestop-demo
spec:
  terminationGracePeriodSeconds: 30
  containers:
    - name: nginx
      image: nginx:1.31-alpine
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

如果 `preStop` 在宽限期到期时仍未完成，kubelet 会请求一次约 2 秒的小幅延长，再继续终止流程；这不是可依赖的常规退出窗口。钩子需要更长时间时，应直接调大 `terminationGracePeriodSeconds`。

> [!TIP]
> 纯等待类的 preStop 也可以使用内置的 `sleep` 动作（Kubernetes v1.34 起 GA），例如 `preStop: {sleep: {seconds: 10}}`，不要求镜像内存在 shell，适合 distroless 这类精简镜像。

创建 Pod 后删除，并观察 preStop 带来的退出等待：

```bash
kubectl create -f prestop-demo.yaml
kubectl get pod prestop-demo
time kubectl delete pod prestop-demo
```

由于 preStop 中执行了 `sleep 10`，Pod 会在 `Terminating` 状态停留一段时间。使用 `time` 包裹删除命令时，可以观察到删除请求等待容器终止的耗时接近 preStop 中的等待时间。`terminationGracePeriodSeconds: 30` 表示 kubelet 最多给容器 30 秒完成 preStop 和进程退出；如果超过该时间仍未退出，容器会被强制终止。

## 修改终止宽限期

当应用需要更长时间完成请求处理、连接关闭或本地清理时，可以调大 `terminationGracePeriodSeconds`。下面示例将宽限期调整为 60 秒，并在 preStop 中等待 45 秒，用于模拟较长的下线收敛过程：

```yaml{6,12-18} [graceful-period-demo.yaml]
apiVersion: v1
kind: Pod
metadata:
  name: graceful-period-demo
spec:
  terminationGracePeriodSeconds: 60
  containers:
    - name: nginx
      image: nginx:1.31-alpine
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

删除过程中，Pod 会先进入 `Terminating`，preStop 执行约 45 秒后容器退出。使用 `time` 包裹删除命令时，可以观察到删除等待时间接近 45 秒。由于宽限期为 60 秒，preStop 和 Nginx 退出仍处于允许范围内。如果将 `terminationGracePeriodSeconds` 设置得小于 preStop 执行时间，例如 10 秒，preStop 还未执行完成时就可能被 kubelet 强制结束。

## 优雅退出建议

可靠的优雅退出通常需要同时满足以下条件：

- readinessProbe 能准确反映 Pod 是否应接入流量
- preStop 给流量入口留出收敛时间
- terminationGracePeriodSeconds 覆盖最长请求的处理时间
- 应用正确处理 SIGTERM
- 发布前通过压测或演练验证
