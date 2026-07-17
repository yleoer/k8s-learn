# Pod 创建与状态观察

Pod 是 Kubernetes 能创建和调度的最小计算单元。它可以包含一个或多个紧密协作的容器，并作为整体被调度到一个 Node；同一 Pod 中的容器共享网络命名空间，只有显式挂载同一 Volume 时才能共享文件。第 08 章继续记录 Pod 的对象结构、多容器协作、镜像策略、资源配置、生命周期和探针，本篇聚焦创建后应如何理解和观察状态。

## 创建最小 Pod

复用[第 08 章的最小 Pod 示例](../08-Pod入门/1-Pod资源定义与基础配置.md#最小-pod-示例)中的完整 `nginx.yaml`。以下命令假设对象创建在 `default` Namespace：

```bash
kubectl create -f nginx.yaml -n default
kubectl get po nginx-demo -o wide
kubectl describe po nginx-demo
```

临时验证也可以使用 `run`：

```bash
kubectl run temp-nginx --image=nginx:1.31-alpine
kubectl get po temp-nginx -o yaml
kubectl delete po temp-nginx
```

`kubectl run` 直接创建裸 Pod，适合一次性的连通性或镜像验证。需要副本管理、滚动更新和故障补建的长运行应用应由 Deployment、StatefulSet 或 DaemonSet 等工作负载控制器创建。

## Pod 状态模型

观察 Pod 时需要区分三个层次：

| 层次 | 位置 | 回答的问题 |
| --- | --- | --- |
| Pod phase | `.status.phase` | Pod 处于生命周期的哪一类高层阶段 |
| Condition | `.status.conditions` | 是否已调度、容器是否就绪等具体条件是否成立 |
| 容器状态 | `.status.containerStatuses` | 某个容器是在等待、运行还是已终止，以及原因和重启次数 |

`kubectl get po` 的 `STATUS` 列是 kubectl 汇总后的便捷显示，不等同于 Pod phase。`READY` 反映就绪容器数量，`RESTARTS` 汇总容器重启次数；需要确认实际字段时，应查看 `kubectl describe po <pod-name>` 或 `kubectl get po <pod-name> -o yaml`。

常见 Pod phase 含义如下：

| phase | 含义 | 操作含义 |
| --- | --- | --- |
| `Pending` | Pod 已被集群接受，但仍有容器未完成设置或准备运行 | 可能仍在等待调度、卷准备或镜像下载 |
| `Running` | Pod 已绑定 Node，全部容器已创建，至少一个容器正在运行、启动或重启 | 不代表应用已经就绪或可被访问 |
| `Succeeded` | 所有容器成功终止，且不会再重启 | 常见于成功完成的 Job |
| `Failed` | 所有容器已终止，且至少一个容器失败或被系统终止并且不再重启 | 需要结合退出码和容器状态判断原因 |
| `Unknown` | 通常因无法与 Pod 所在 Node 通信，无法取得 Pod 状态 | 优先检查 Node、kubelet 和节点网络 |

## 容器等待原因

`ErrImagePull`、`ImagePullBackOff` 和 `CrashLoopBackOff` 通常显示在 `STATUS` 列或容器状态原因中，而不是 Pod phase：

| 原因 | 含义 | 首要观察点 |
| --- | --- | --- |
| `ErrImagePull` | 本次拉取镜像尝试失败 | 镜像名称、标签、凭据、仓库连通性和证书 |
| `ImagePullBackOff` | 拉取持续失败，kubelet 正在按退避间隔重试 | 同时查看 `describe` 中的最近拉取事件 |
| `CrashLoopBackOff` | 容器启动后反复退出，kubelet 按重启策略等待后重试 | 当前和上一轮日志、启动命令、配置、依赖和探针 |

`--previous` 只读取同一容器上一次已终止实例的日志，因此特别适合 CrashLoopBackOff；如果容器从未重启或日志已经被节点清理，则不会有可读结果。

## 基础观察路径

```bash
kubectl get po -o wide
kubectl describe po <pod-name>
kubectl get ev --sort-by=.metadata.creationTimestamp
kubectl logs <pod-name>
kubectl logs <pod-name> --previous
```

`get -o wide` 先确认 Pod IP、Node 和摘要状态；`describe` 展示调度、容器状态和关联 Event；Event 反映调度器、kubelet 或存储组件近期报告的动作；日志最后用于定位容器和应用进程本身的失败原因。通用命令的信息来源与边界见[资源查询与排障](./3-资源查询与排障.md)。

`Pending` 常与以下条件有关：

| 条件 | 含义 |
| --- | --- |
| 节点资源不足 | 没有 Node 能满足 Pod 声明的资源请求 |
| 节点选择约束 | Node Label、nodeSelector、亲和性或拓扑约束未找到可用 Node |
| 污点与容忍 | Node 的污点拒绝该 Pod，且 Pod 没有匹配容忍 |
| PVC 未绑定 | Pod 依赖的 PersistentVolumeClaim（持久卷声明）尚未获得可用卷 |

这些条件决定调度器能否选择节点，或 kubelet 能否准备运行环境。资源请求与调度排查在第 08、14、15 章展开，PVC 与存储供给在第 12 章展开。

## 裸 Pod 与控制器

裸 Pod 是用户直接创建、没有上层工作负载控制器管理的 Pod。它适合验证镜像、命令或网络，但不会自行补齐副本、执行滚动更新或在节点故障后由控制器创建替代实例。

Deployment、StatefulSet 和 DaemonSet 是管理 Pod 的控制器：它们分别面向可替换副本、有稳定身份的实例和节点覆盖场景。删除控制器管理的 Pod 不会缩容；控制器发现实际数量低于期望后会创建替代 Pod。工作负载选择和控制器行为在第 09 章展开。

## 参考

- [Pod](https://kubernetes.io/docs/concepts/workloads/pods/)
- [工作负载](https://kubernetes.io/docs/concepts/workloads/)
