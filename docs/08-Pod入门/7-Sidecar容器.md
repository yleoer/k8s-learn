# Sidecar 容器

Pod 内常见由辅助容器为主容器提供日志采集、网络代理或配置同步能力。[Pod 资源定义与基础配置](./1-Pod资源定义与基础配置.md) 中的多容器示例把辅助进程放在 `containers` 列表里，这种方式无法约定启动和退出顺序。原生 Sidecar 容器解决的正是顺序问题：辅助容器先于主容器就绪、晚于主容器退出，生命周期与 Pod 一致。该特性自 Kubernetes v1.33 起为稳定特性，v1.29 起默认启用。

## 定义方式

Sidecar 容器写在 `initContainers` 中，并将容器级 `restartPolicy` 设置为 `Always`。这是它与普通 Init Container 的唯一定义差异：

```yaml [sidecar-demo.yaml]
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sidecar-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sidecar-demo
  template:
    metadata:
      labels:
        app: sidecar-demo
    spec:
      initContainers:
        - name: logshipper
          image: busybox:1.36.1
          restartPolicy: Always
          command: ["sh", "-c", "tail -F /opt/logs.txt"]
          volumeMounts:
            - name: data
              mountPath: /opt
      containers:
        - name: app
          image: busybox:1.36.1
          command: ["sh", "-c", "while true; do echo logging >> /opt/logs.txt; sleep 1; done"]
          volumeMounts:
            - name: data
              mountPath: /opt
      volumes:
        - name: data
          emptyDir: {}
```

创建后观察容器状态和 Sidecar 输出：

```bash
kubectl apply -f sidecar-demo.yaml
kubectl get pod -l app=sidecar-demo
kubectl logs deployment/sidecar-demo -c logshipper -f
```

`READY` 列会显示 `2/2`：Sidecar 容器计入 Pod 的容器总数和就绪判断。

## 生命周期行为

Sidecar 容器与普通 Init Container、普通容器的行为差异如下：

| 行为     | 普通 Init Container        | Sidecar 容器                         | 普通容器                     |
|--------|--------------------------|------------------------------------|--------------------------|
| 启动时机   | 按定义顺序依次执行                | 按 `initContainers` 顺序启动，启动后即继续后续容器 | Init 阶段完成后启动             |
| 是否需要退出 | 必须成功退出才能继续               | 不退出，随 Pod 全程运行                     | 随应用运行                    |
| 探针支持   | 不支持                      | 支持 startup、liveness、readiness 探针   | 支持                       |
| 失败处理   | 按 Pod `restartPolicy` 处理 | 始终重启，不影响 Pod 整体状态                  | 按 Pod `restartPolicy` 处理 |
| 终止顺序   | 已退出                      | 主容器完全停止后，按定义逆序终止                   | 收到终止信号后退出                |

几个值得记录的细节：

- kubelet 启动 Sidecar 后不等它退出，而是在其 `started` 状态变为 true 后就继续处理下一个 Init Container。定义了 `startupProbe` 时，探针成功才算启动完成，因此 Sidecar 的 startupProbe 可以用来精确控制后续初始化的依赖顺序。
- Sidecar 的 `readinessProbe` 结果参与 Pod 的 Ready 判断。代理类 Sidecar 未就绪时，Pod 不会被 Service 接入流量。
- Pod 终止时 Sidecar 最后收到信号。如果主容器耗尽了整个终止宽限期，Sidecar 会被紧接着强制终止，来不及优雅退出，此时的非零退出码属于正常现象。
- 只修改 Sidecar 的镜像会原地重启该容器，不会重建整个 Pod。

## 与 Job 协作

Sidecar 进入 `initContainers` 之前，Job 中的辅助容器是长期痛点：放在 `containers` 里的日志或代理容器不会退出，主任务完成后 Job 无法进入完成状态。Sidecar 容器不阻塞 Job 完成——主容器结束后，Sidecar 由 kubelet 负责终止，Job 正常判定成功。

## 记录要点

- Sidecar 的判定标准只有一个：`initContainers` 中容器级 `restartPolicy: Always`。
- Kubernetes v1.33 和 v1.34 中，`initContainers` 的容器级 `restartPolicy` 只允许 `Always`；v1.35 起 `ContainerRestartRules` 特性进入 Beta 并默认启用，普通容器和 Init Container 也可以设置容器级重启策略，但 Sidecar 的定义不变。
- 需要保证启动顺序或退出顺序的辅助容器应使用 Sidecar；与主容器完全对等、无顺序要求的多容器协作仍可放在 `containers` 中。
- Sidecar 与主容器共享 Pod 的资源边界，资源 requests 和 limits 需要与主容器一并规划。

## 参考

- [Sidecar Containers](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/)
- [Init Containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)
- [Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
