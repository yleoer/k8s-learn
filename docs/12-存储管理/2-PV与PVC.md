# PV 与 PVC

PersistentVolume 表示集群可用的一份存储，PersistentVolumeClaim 表示用户对存储的请求。PV 是集群级资源，PVC 属于命名空间；Pod 与它引用的 PVC 必须位于同一命名空间。

## 供给与绑定

PV 可以由管理员预先创建，也可以在 PVC 出现后由 StorageClass 动态供给。控制平面根据以下条件匹配 PV 与 PVC：

- PV 可用容量不小于 PVC 的请求容量。
- `storageClassName` 相同。
- PV 支持 PVC 请求的全部访问模式。
- `volumeMode` 兼容，默认为 `Filesystem`。
- PVC 的标签选择器能够匹配 PV；带非空 `selector` 的 PVC 不能动态供给。

绑定是一对一关系。较大的 PV 可以满足较小的 PVC，但剩余容量不会再分配给其他 PVC。找不到匹配 PV 且没有可用动态供给器时，PVC 会保持 `Pending`。

## 访问模式

| 模式                 | 缩写   | 含义                                 |
|--------------------|------|------------------------------------|
| `ReadWriteOnce`    | RWO  | 可由单个节点以读写方式挂载；同一节点上的多个 Pod 仍可能同时访问 |
| `ReadOnlyMany`     | ROX  | 可由多个节点以只读方式挂载                      |
| `ReadWriteMany`    | RWX  | 可由多个节点以读写方式挂载                      |
| `ReadWriteOncePod` | RWOP | 整个集群中只能由单个 Pod 以读写方式挂载，仅适用于 CSI 卷  |

访问模式用于 PV/PVC 匹配，并不普遍充当挂载后的写保护机制；`ReadWriteOncePod` 是确保单 Pod 独占的模式。后端是否支持某种模式取决于驱动和存储系统，NFS 常见为 RWX，许多块存储只支持 RWO 或 RWOP。

`volumeMode: Filesystem` 会把卷挂载为目录，也是默认值；`volumeMode: Block` 会把原始块设备通过 `volumeDevices` 提供给容器，应用需要自行处理文件系统或块设备格式。

## 静态 NFS 示例

以下清单定义一个静态 NFS PV、一个 PVC 和消费该 PVC 的 Pod。NFS 服务器与 `/srv/nfs/k8s/static` 导出目录必须提前存在。

```yaml [nfs-static-storage.yaml]
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-static-pv
spec:
  capacity:
    storage: 10Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: nfs-static
  mountOptions:
    - hard
    - nfsvers=4.1
  nfs:
    server: <nfs-server-ip>
    path: /srv/nfs/k8s/static
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-static-pvc
spec:
  accessModes:
    - ReadWriteMany
  volumeMode: Filesystem
  storageClassName: nfs-static
  resources:
    requests:
      storage: 5Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: nfs-static-writer
spec:
  restartPolicy: Never
  containers:
    - name: writer
      image: busybox:1.38
      command: ["sh", "-c", "date -Iseconds >> /data/history.log && sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: nfs-static-pvc
```

```bash
kubectl create -f nfs-static-storage.yaml
kubectl get pv nfs-static-pv
kubectl get pvc nfs-static-pvc
kubectl describe pod nfs-static-writer
```

清单中的 `10Gi` 是 Kubernetes 用于匹配和展示的容量。普通 NFS 导出并不会因为该数值自动产生 10 GiB 配额，实际限制需要由 NFS 后端的文件系统配额或存储系统实现。

## 生命周期状态

PV 常见阶段如下：

| 阶段          | 含义                             |
|-------------|--------------------------------|
| `Available` | 尚未绑定 PVC                       |
| `Bound`     | 已与 PVC 一对一绑定                   |
| `Released`  | PVC 已删除，但存储还没有完成回收，不能直接绑定新 PVC |
| `Failed`    | 自动回收失败                         |

PVC 正在被 Pod 使用时，`kubernetes.io/pvc-protection` finalizer 会延迟删除 PVC；PV 仍绑定 PVC 时，`kubernetes.io/pv-protection` 会延迟删除 PV。对 `Delete` 回收策略，CSI 外部供给器 finalizer 还会确保后端卷删除完成后再移除 PV 对象。

## 回收策略

回收策略决定 PVC 删除并释放 PV 后如何处理存储：

| 策略        | 行为                                          |
|-----------|---------------------------------------------|
| `Retain`  | 保留 PV 对应的后端数据，需要管理员确认、清理和重新建模               |
| `Delete`  | 驱动支持时删除 PV 对象和后端卷；动态 PV 继承 StorageClass 的策略 |
| `Recycle` | 只做基础目录清理，已经弃用，不应再用于新配置                      |

StorageClass 未显式指定时，动态供给 PV 的回收策略默认为 `Delete`。生产数据应根据备份和恢复目标明确设置，不能把动态供给等同于自动保留。

> [!CAUTION]
> 删除 PVC 可能触发后端卷和数据删除。执行前先查看绑定 PV、回收策略、StorageClass、快照或备份状态，不要只根据 PVC 名称判断影响范围。

## 预绑定与保留卷

PVC 可以通过 `spec.volumeName` 指定现有 PV，PV 也可以通过 `spec.claimRef` 为特定命名空间和 PVC 预留。预绑定会绕过部分常规匹配检查，因此仍要人工确认容量、访问模式、StorageClass、卷模式和节点亲和性确实兼容。

需要明确请求“无存储类”的静态 PV 时，PV 与 PVC 都应写 `storageClassName: ""`。省略 PVC 的 `storageClassName` 并不等价：集群存在默认 StorageClass 时，控制面可能为它补上默认类并触发动态供给。

`Retain` PV 复用时，通常先确认后端数据，再清除旧 `claimRef`，创建指向该 PV 的新 PVC。整个过程应在工作负载停止且数据一致性得到确认后进行。

## 清理示例

本页示例使用 `Retain`，删除 PVC 后 NFS 数据不会自动清除：

```bash
kubectl delete pod nfs-static-writer
kubectl delete pvc nfs-static-pvc
kubectl get pv nfs-static-pv
```

PV 进入 `Released` 后，由管理员检查 NFS 目录并决定保留、迁移或删除。确认不再需要对应存储表示时，再删除 PV：

```bash
kubectl delete pv nfs-static-pv
```

删除 `Retain` PV 对象不会删除 NFS 目录中的数据。
