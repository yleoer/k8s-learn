# 存储管理速查

本章整理 Volume、PV、PVC、StorageClass 与 CSI 的观察和排障命令。PVC 表达应用的存储请求，PV 或 CSI 驱动提供实际卷；资源对象存在不表示后端存储必定可用。

## 关键对象与边界

| 对象 | 作用 | 不负责 |
| --- | --- | --- |
| Volume | 为 Pod 提供挂载入口 | 跨 Pod 保留数据的承诺 |
| PVC | 请求容量、访问模式和 StorageClass | 创建后端卷的具体实现 |
| StorageClass | 选择动态供给策略 | 替代 CSI 驱动 |
| CSI | 实现卷供给、挂载和快照能力 | 应用一致性备份 |

## 命令速查

### 存储资源观察

```bash
kubectl get pv
kubectl get pvc -A
kubectl get sc
kubectl describe pvc <pvc-name>
kubectl describe pv <pv-name>
```

### Pod 挂载与事件

```bash
kubectl get po -n <namespace> -o wide
kubectl describe po <pod-name> -n <namespace>
kubectl get ev -n <namespace> --sort-by=.metadata.creationTimestamp
kubectl get csidriver
```

### 扩容与快照

```bash
kubectl get volumesnapshot -A
kubectl describe volumesnapshot <snapshot-name> -n <namespace>
kubectl get pvc <pvc-name> -o yaml
```

## 配置速查

| 配置 | 检查重点 |
| --- | --- |
| `accessModes` | 请求能力，不等同于底层驱动一定支持 |
| `storageClassName` | 必须存在相应供给器或静态 PV |
| `resources.requests.storage` | PVC 请求容量，受配额和后端容量约束 |
| `reclaimPolicy` | PVC 删除后 PV 与后端数据的处理策略 |

## 排查索引

| 现象 | 优先检查 | 正文 |
| --- | --- | --- |
| PVC 长期 Pending | StorageClass、CSI 供给器、配额与事件 | [StorageClass 与动态供给](./3-StorageClass与动态供给.md) |
| Pod 挂载失败 | PVC 绑定、节点条件、CSI 日志 | [Volume 与临时存储](./1-Volume与临时存储.md) |
| 快照不可用 | Snapshot controller、驱动能力与 VolumeSnapshotClass | [扩容快照与排障](./5-扩容快照与排障.md) |

## 关联页面

- [PV 与 PVC](./2-PV与PVC.md)
- [NFS 与 CSI 动态存储](./4-NFS与CSI动态存储.md)

## 参考

- [持久卷](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
