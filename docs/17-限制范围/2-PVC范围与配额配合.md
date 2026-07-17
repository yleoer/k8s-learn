# PVC 范围与配额配合

PVC 的 LimitRange 用于限制单个声明的存储请求大小，ResourceQuota 用于限制命名空间累计请求。两者分别处理“单次不能过大”和“总量不能超额”。

## 限制 PVC 大小

```yaml [team-a-pvc-limits.yaml]
apiVersion: v1
kind: LimitRange
metadata:
  name: team-a-pvc-limits
  namespace: team-a
spec:
  limits:
    - type: PersistentVolumeClaim
      min:
        storage: 1Gi
      max:
        storage: 50Gi
```

```bash
kubectl create -f team-a-pvc-limits.yaml
```

该清单不能替代 [ResourceQuota 的 `requests.storage`](/16-资源配额/2-配额范围与存储)。PVC 是否最终绑定还取决于 StorageClass、CSI 驱动、访问模式、卷绑定模式和后端容量。

> [!NOTE]
> LimitRange 不能为 PVC 自动选择 StorageClass，也不直接设置目录配额。NFS 等后端的实际容量隔离必须由存储系统和 CSI 实现保证。

## 参考

- [LimitRange 示例](https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/memory-constraint-namespace/)
- [StorageClass](https://kubernetes.io/docs/concepts/storage/storage-classes/)
