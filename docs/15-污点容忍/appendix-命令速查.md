# 污点容忍速查

本章整理节点污点、Pod 容忍与节点维护操作。污点用于排斥不匹配 Pod，容忍只允许放置或继续运行，不会要求 Pod 一定选择该节点。

## 关键对象与边界

| 对象 | 作用 | 不负责 |
| --- | --- | --- |
| taint | 排斥不匹配 Pod | 选择专用节点 |
| toleration | 忽略匹配污点 | 保证进入对应节点 |
| cordon | 阻止新的普通调度 | 驱逐已运行 Pod |
| drain | 通过驱逐 API 迁移工作负载 | 忽略 PDB 或保存 `emptyDir` 数据 |

## 命令速查

### 污点观察与变更

```bash
kubectl describe no <node-name>
kubectl taint no <node-name> maintenance.example.com/window=true:NoSchedule
kubectl taint no <node-name> maintenance.example.com/window=true:NoSchedule-
kubectl get po -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,TOLERATIONS:.spec.tolerations'
```

### 计划维护

```bash
kubectl cordon <node-name>
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
kubectl uncordon <node-name>
```

## 配置速查

| 配置 | 检查重点 |
| --- | --- |
| `NoSchedule` | 阻止新的不容忍 Pod，不驱逐已有 Pod |
| `PreferNoSchedule` | 调度器尽量避免，不是硬保证 |
| `NoExecute` | 影响新 Pod 与已运行 Pod |
| `tolerationSeconds` | 仅用于 `NoExecute` 的继续运行时长 |

## 排查索引

| 现象 | 优先检查 | 正文 |
| --- | --- | --- |
| `had untolerated taint` | key、operator、value、effect | [污点操作与排障](./4-污点操作与排障.md) |
| 节点维护后 Pod 未迁移 | Pod owner、PDB、DaemonSet 与 `emptyDir` | [节点维护与故障](./3-节点维护与故障.md) |
| 专用节点混入其他工作负载 | 容忍与节点亲和性是否组合使用 | [专用节点隔离](./2-专用节点隔离.md) |

## 关联页面

- [污点效果与匹配](./1-污点效果与匹配.md)
- [调度策略](../14-调度策略/index.md)

## 参考

- [污点与容忍](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
