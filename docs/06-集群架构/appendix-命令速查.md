# 集群架构速查

本章梳理控制面、工作节点和 Kubernetes 核心资源的边界。控制面保存并协调期望状态，节点组件负责本地执行；命令输出只能辅助观察，不能替代对象关系的判断。

## 关键对象与边界

| 对象 | 作用 | 不负责 |
| --- | --- | --- |
| kube-apiserver | API 请求入口与对象校验 | 持续协调资源 |
| etcd | 保存集群状态 | 直接调度或运行容器 |
| scheduler | 为未绑定 Pod 选择节点 | 创建工作负载副本 |
| kubelet | 在节点执行 Pod 规范 | 跨节点服务发现 |

## 命令速查

### 集群与组件观察

```bash
kubectl cluster-info
kubectl get no
kubectl get po -n kube-system
kubectl get --raw='/readyz?verbose'
```

### 对象与事件观察

```bash
kubectl api-resources
kubectl get ev -A --sort-by=.metadata.creationTimestamp
kubectl describe no <node-name>
kubectl explain pod.spec
```

## 配置速查

| 关系 | 检查重点 |
| --- | --- |
| 控制器与期望状态 | `spec` 表达期望，`status` 记录观察结果 |
| Pod 调度 | scheduler 绑定节点后，kubelet 才创建 sandbox 和容器 |
| Service 访问 | Service、EndpointSlice、DNS 与数据面共同参与 |

## 排查索引

| 现象 | 优先检查 | 正文 |
| --- | --- | --- |
| API 请求异常 | API Server 就绪状态与认证授权 | [控制节点组件](./4-控制节点组件.md) |
| Pod 长期 Pending | scheduler 事件与节点条件 | [工作节点组件](./5-工作节点组件.md) |
| 概念边界不清 | 核心资源与抽象关系 | [核心资源与抽象](./6-核心资源与抽象.md) |

## 关联页面

- [Kubernetes 基本概念](./1-Kubernetes基本概念.md)
- [Kubernetes 架构全景](./3-Kubernetes架构全景.md)

## 参考

- [Kubernetes 组件](https://kubernetes.io/docs/concepts/overview/components/)
