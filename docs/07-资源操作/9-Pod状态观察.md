# Pod 状态观察

Pod 状态是判断应用是否正常运行的第一入口。本章只记录状态观察和基础排查入口，资源配置、镜像拉取、生命周期和探针等细节在第 08 章继续展开。

## 查看 Pod 状态

常用命令：

```bash
kubectl get pod
kubectl get pod -o wide
kubectl describe pod <pod-name>
kubectl logs <pod-name>
kubectl get events --sort-by=.metadata.creationTimestamp
```

`get` 看摘要，`describe` 看详情和事件，`logs` 看容器输出，`events` 看集群调度和运行事件。

## 常见状态

| 状态 | 含义 | 常见原因 |
| --- | --- | --- |
| `Pending` | Pod 已创建但尚未运行 | 调度失败、镜像拉取前等待、PVC 未绑定 |
| `Running` | Pod 已绑定节点，至少一个容器在运行 | 正常运行或部分容器异常 |
| `Succeeded` | 所有容器成功退出 | Job 或一次性任务正常完成 |
| `Failed` | 所有容器退出且至少一个失败 | 命令执行失败、退出码非 0 |
| `Unknown` | 无法获取 Pod 状态 | 节点失联或 kubelet 异常 |

需要注意，`STATUS` 列中还可能显示 `CrashLoopBackOff`、`ImagePullBackOff` 等状态，它们并不是 Pod 的 phase，而是更具体的容器状态原因。

## Pending 观察

`Pending` 表示 Pod 还没有真正运行。排查步骤：

```bash
kubectl describe pod <pod-name>
kubectl get events --sort-by=.metadata.creationTimestamp
kubectl get node
```

常见原因包括：

- 节点资源不足
- 节点选择器或亲和性不匹配
- 污点没有对应容忍
- PVC 没有绑定成功
- 镜像拉取前处于等待阶段

重点看 `describe` 输出中的 `Events`，具体调度和资源不足排查在第 08 章继续记录。

## 镜像拉取状态

镜像拉取失败通常会看到 `ErrImagePull` 或 `ImagePullBackOff`。

排查步骤：

```bash
kubectl describe pod <pod-name>
kubectl get pod <pod-name> -o yaml
```

常见原因：

- 镜像名称或标签写错
- 私有仓库未配置拉取凭据
- 节点无法访问镜像仓库
- 镜像仓库证书或协议配置错误
- 镜像体积过大导致拉取超时

如果是私有仓库，需要检查 `imagePullSecrets`。镜像拉取策略和私有仓库认证放在第 08 章继续记录。

## CrashLoopBackOff

`CrashLoopBackOff` 表示容器不断启动、退出、再重启。

排查步骤：

```bash
kubectl logs <pod-name>
kubectl logs <pod-name> --previous
kubectl describe pod <pod-name>
```

常见原因：

- 应用启动命令错误
- 缺少配置文件或环境变量
- 程序启动后立即退出
- 健康检查配置不合理
- 依赖的数据库或中间件不可用

`--previous` 可以查看上一轮已崩溃容器的日志，通常比当前容器的日志更有价值。启动命令、环境变量、生命周期钩子和探针配置需要结合第 08 章的 Pod 配置内容继续分析。

## Running 但不可访问

Pod 处于 `Running` 不代表业务一定可用。排查步骤：

```bash
kubectl get pod <pod-name> -o wide
kubectl describe pod <pod-name>
kubectl logs <pod-name>
kubectl exec -it <pod-name> -- sh
```

常见原因：

- 应用进程没有监听预期端口
- 容器内服务只监听 `127.0.0.1`
- Service 标签选择器不匹配
- NetworkPolicy 阻断流量
- 应用健康检查失败但进程未退出

记录 Service 后，还需要结合 `kubectl get endpointslices` 排查服务发现问题。

## Unknown

`Unknown` 通常表示控制面无法获取 Pod 所在节点的状态。

排查步骤：

```bash
kubectl get node
kubectl describe node <node-name>
kubectl get pod -o wide
```

常见原因：

- 节点宕机
- kubelet 异常
- 节点网络不可达
- APIServer 与节点通信异常

这类问题更偏向节点或集群组件层面的排障。

## 观察顺序

建议形成固定流程：

```bash
kubectl get pod -o wide
kubectl describe pod <pod-name>
kubectl logs <pod-name>
kubectl logs <pod-name> --previous
kubectl get events --sort-by=.metadata.creationTimestamp
```

观察时按层次判断：

- 是否调度到节点
- 镜像是否拉取成功
- 容器是否成功启动
- 应用日志是否报错
- 健康检查是否失败
- 配置、存储、网络是否满足要求

大部分 Pod 的初级问题，都能通过状态、事件和日志定位到大致方向。后续进入第 08 章后，再围绕具体字段和生命周期阶段展开细化排查。
