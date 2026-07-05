# 临时容器与 Pod 调试

生产镜像通常裁剪掉 shell 和调试工具，distroless 这类镜像甚至没有 `sh`，`kubectl exec` 在这些场景中无从下手；容器已经崩溃时，`exec` 更是完全不可用。临时容器（ephemeral container）为运行中的 Pod 临时附加一个带工具的容器，`kubectl debug` 是它的主要入口，同时还覆盖复制 Pod 和节点调试两种方式。

## 临时容器

临时容器自 Kubernetes v1.25 起为稳定特性。它与普通容器写在同一个 Pod 中，但边界完全不同：

- 没有资源保证与执行保证，不允许设置 `resources`，退出后不会自动重启。
- 不允许配置 `ports`、`livenessProbe`、`readinessProbe`、`startupProbe`。
- 通过 Pod 的 `ephemeralcontainers` 子资源添加，不能直接修改 `pod.spec` 加入，因此 `kubectl edit` 无法添加。
- 添加之后不能修改，也不能从 Pod 中移除；临时容器进程退出后，记录仍保留在 Pod 状态中。

这些限制决定了它只用于观察和排障，不承载业务逻辑。

## 调试运行中的 Pod

先创建一个目标 Pod：

```bash
kubectl run debug-demo --image=nginx:stable-alpine
```

向 Pod 注入临时容器并进入交互 shell：

```bash
kubectl debug -it debug-demo --image=busybox:1.36.1 --target=debug-demo -- sh
```

`--target=<container>` 让临时容器加入目标容器的进程命名空间，才能看到目标容器的进程；该能力需要容器运行时支持，containerd 支持该行为。进入后验证可以观察到 nginx 进程和网络：

```bash
ps aux
wget -qO- http://127.0.0.1
```

查看 Pod 中已注入的临时容器：

```bash
kubectl describe pod debug-demo
```

::: details Ephemeral Containers 部分输出类似如下

```text
Ephemeral Containers:
  debugger-8xzmp:
    Container ID:   containerd://e2e152b9...
    Image:          busybox:1.36.1
    State:          Running
```

:::

## 复制 Pod 调试

Pod 处于 CrashLoopBackOff、需要修改启动命令或换镜像验证时，可以复制出一个调试副本，不影响原 Pod：

```bash
kubectl debug debug-demo -it --copy-to=debug-demo-copy --container=debug-demo -- sh
```

常用参数组合：

| 参数                                | 作用                                  |
|-----------------------------------|-------------------------------------|
| `--copy-to=<name>`                | 以原 Pod 为模板创建副本                      |
| `--container` / `-c`              | 指定修改启动命令的目标容器，不指定时新增一个调试容器          |
| `--set-image=<container>=<image>` | 修改副本中容器镜像，`*=busybox:1.36.1` 表示全部容器 |
| `--share-processes`               | 副本内容器共享进程命名空间                       |

例如把副本的所有容器换成带工具的镜像：

```bash
kubectl debug debug-demo --copy-to=debug-demo-img --set-image=*=busybox:1.36.1 -- sleep 3600
```

副本 Pod 不受原控制器管理，调试完成后需要手动删除：

```bash
kubectl delete pod debug-demo-copy debug-demo-img
```

## 节点调试

`kubectl debug node/` 在目标节点上创建调试 Pod，用于没有节点 SSH 权限时的排障：

```bash
kubectl debug node/<node-name> -it --image=busybox:1.36.1
```

调试 Pod 的名称形如 `node-debugger-<node-name>-<suffix>`，节点根文件系统挂载在容器内的 `/host`，容器运行在宿主机的 IPC、Network 和 PID 命名空间中，可以直接观察节点进程和网络。

默认创建的不是特权 Pod：读取部分进程信息可能失败，`chroot /host` 也可能失败。需要完整宿主机权限时使用 `--profile=sysadmin`：

```bash
kubectl debug node/<node-name> -it --profile=sysadmin --image=busybox:1.36.1
```

调试结束后删除调试 Pod：

```bash
kubectl delete pod node-debugger-<node-name>-<suffix>
```

## 调试 profile

`--profile` 控制调试容器或调试 Pod 的安全属性：

| profile      | 行为                                    |
|--------------|---------------------------------------|
| `legacy`     | 未指定时的默认值，兼容历史行为，官方已计划弃用               |
| `general`    | 通用调试配置，官方推荐的默认选择                      |
| `baseline`   | 满足 Pod Security Standards baseline 策略 |
| `restricted` | 满足 restricted 策略，适合受限命名空间             |
| `netadmin`   | 附加 `NET_ADMIN` 等网络管理能力                |
| `sysadmin`   | 特权模式，节点级排障使用                          |

新记录统一显式指定 `--profile`，避免依赖将被弃用的 `legacy` 默认值。

## 记录要点

- 临时容器适合观察运行中的 Pod；复制 Pod 适合改命令、换镜像做对照实验；节点调试面向节点层问题。
- `--target` 依赖运行时支持，进程不可见时先确认该参数和运行时行为。
- 静态 Pod 不支持临时容器，控制面组件排障走节点调试或 `crictl`。
- 调试副本和节点调试 Pod 不会自动回收，结束后应删除。
- 生产 Namespace 受 Pod Security Standards 约束时，选择能通过策略的 profile。

## 参考

- [Ephemeral Containers](https://kubernetes.io/docs/concepts/workloads/pods/ephemeral-containers/)
- [Debug Running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/)
- [kubectl debug](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_debug/)
