# Pod 命令速查

本章以 Pod 为最小工作负载单元整理创建、观察、调试与退出命令。Pod 是容器共享网络和存储上下文的运行单元，不替代 Deployment 等控制器提供的副本维护能力。

## 关键对象与边界

| 对象 | 作用 | 不负责 |
| --- | --- | --- |
| Pod | 承载一个或多个协作容器 | 维持业务副本数量 |
| probe | 影响容器重启或服务端点就绪 | 修复应用逻辑错误 |
| ephemeral container | 为运行中 Pod 提供调试环境 | 参与常规流量或重启策略 |

## 命令速查

### 创建与观察

```bash
kubectl create -f nginx.yaml
kubectl get po
kubectl get po <pod-name> -o wide
kubectl describe po <pod-name>
kubectl get po <pod-name> -o yaml
```

### 日志与容器调试

```bash
kubectl logs <pod-name>
kubectl logs <pod-name> -c <container-name>
kubectl exec -it <pod-name> -c <container-name> -- sh
kubectl debug -it <pod-name> --image=busybox:1.38
```

### 生命周期与清理

```bash
kubectl get ev --field-selector involvedObject.name=<pod-name>
kubectl delete po <pod-name>
kubectl wait --for=condition=Ready po/<pod-name> --timeout=60s
```

## 配置速查

| 配置 | 检查重点 |
| --- | --- |
| resources | requests 参与调度，limits 约束运行时资源 |
| restartPolicy | `Always`、`OnFailure`、`Never` 的适用控制器不同 |
| probes | startup、readiness、liveness 的失败后果不同 |
| tolerations | 容忍污点不等于要求调度到该节点 |

## 排查索引

| 现象 | 优先检查 | 正文 |
| --- | --- | --- |
| `ImagePullBackOff` | 镜像、仓库凭据、Pod 事件 | [镜像拉取与重启策略](./4-Pod镜像拉取与重启策略.md) |
| 未进入 Service 后端 | readiness、EndpointSlice、标签 | [健康检查与探针配置](./6-Pod健康检查与探针配置.md) |
| 容器无法调试 | 临时容器权限与目标容器状态 | [临时容器与 Pod 调试](./9-临时容器与Pod调试.md) |

## 关联页面

- [Pod 资源定义与基础配置](./1-Pod资源定义与基础配置.md)
- [Pod 生命周期与优雅退出](./5-Pod生命周期与优雅退出.md)
- [Sidecar 容器](./7-Sidecar容器.md)

## 参考

- [Pod 生命周期](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
