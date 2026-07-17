# NFS 与 CSI 动态存储

NFS CSI 驱动连接已经存在的 NFSv3 或 NFSv4 服务器，通过为每个 PVC 创建独立子目录实现动态供给。驱动本身不部署 NFS 服务，也不会自动提供后端复制、配额或备份。

本页以 Ubuntu 24.04 实验环境为例，使用独立 NFS 服务器和 Kubernetes NFS CSI Driver v4.13.4。地址与网段使用占位符，执行前应替换为实验环境实际值。

## 准备 NFS 服务

在独立 NFS 服务器安装组件：

```bash
sudo apt update
sudo apt install -y nfs-kernel-server
sudo mkdir -p /srv/nfs/k8s
sudo chown 65534:65534 /srv/nfs/k8s
sudo chmod 0770 /srv/nfs/k8s
```

添加导出配置，只允许集群节点网段访问：

```text [/etc/exports]
/srv/nfs/k8s <node-cidr>(rw,sync,no_subtree_check,root_squash)
```

`<node-cidr>` 应替换为节点所在网段，例如使用 CIDR 表达的实验网络。保留默认安全语义 `root_squash`，不要为方便写入直接改成 `no_root_squash`；如果应用使用固定非 root UID/GID，还要按实际安全上下文调整目录属主和权限。

加载配置并启用服务：

```bash
sudo exportfs -rav
sudo systemctl enable --now nfs-kernel-server
sudo exportfs -v
```

生产 NFS 还需要规划防火墙、身份认证、网络隔离、文件系统配额、高可用和备份，本页配置只用于实验集群验证。

## 准备 Kubernetes 节点

在所有可能运行使用 NFS 卷 Pod 的 Linux 节点安装客户端工具：

```bash
sudo apt update
sudo apt install -y nfs-common
```

可在节点临时验证导出是否可达：

```bash
showmount -e <nfs-server-ip>
sudo mkdir -p /mnt/nfs-test
sudo mount -t nfs4 <nfs-server-ip>:/srv/nfs/k8s /mnt/nfs-test
mount | grep /mnt/nfs-test
sudo umount /mnt/nfs-test
```

## 安装 NFS CSI 驱动

使用上游仓库固定标签安装 v4.13.4：

```bash
git clone --branch v4.13.4 --depth 1 \
  https://github.com/kubernetes-csi/csi-driver-nfs.git
cd csi-driver-nfs
./deploy/install-driver.sh v4.13.4 local
```

检查控制器、节点插件和驱动注册：

```bash
kubectl -n kube-system get po -l app=csi-nfs-controller -o wide
kubectl -n kube-system get po -l app=csi-nfs-node -o wide
kubectl get csidriver nfs.csi.k8s.io
```

控制器通常以 Deployment 运行，负责供给等控制面操作；节点插件通常以 DaemonSet 运行，在各节点执行挂载。两者都正常后再创建 StorageClass。

## 创建 StorageClass

把 `<nfs-server-ip>` 替换为 NFS 服务器地址：

```yaml [nfs-csi-storageclass.yaml]
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-csi
provisioner: nfs.csi.k8s.io
parameters:
  server: <nfs-server-ip>
  share: /srv/nfs/k8s
  subDir: '${pvc.metadata.namespace}/${pvc.metadata.name}'
reclaimPolicy: Retain
volumeBindingMode: Immediate
allowVolumeExpansion: true
mountOptions:
  - nfsvers=4.1
```

```bash
kubectl create -f nfs-csi-storageclass.yaml
kubectl get sc nfs-csi
```

`subDir` 按命名空间和 PVC 名称组织目录。`Retain` 会在 PVC 删除后保留 PV 和 NFS 数据，适合学习和需要人工确认的数据；如果改为 `Delete`，还要结合驱动 `onDelete` 参数和后端备份策略明确目录的删除、保留或归档行为。

NFS 不受可用区拓扑限制，使用 `Immediate` 即可。`allowVolumeExpansion` 允许增大 PVC 声明容量，但基于普通目录的 NFS 动态卷不会因此自动获得文件系统配额，实际可用空间仍由 NFS 服务端控制。

## 验证动态供给

创建 PVC 和 Pod：

```yaml [nfs-csi-demo.yaml]
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-csi-data
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: nfs-csi
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: nfs-csi-writer
spec:
  restartPolicy: Never
  containers:
    - name: writer
      image: busybox:1.38
      command:
        - sh
        - -c
        - echo "$(date -Iseconds) ${POD_NAME}" >> /data/history.log && sleep 3600
      env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: nfs-csi-data
```

```bash
kubectl create -f nfs-csi-demo.yaml
kubectl get pvc nfs-csi-data
kubectl get pv
kubectl exec nfs-csi-writer -- cat /data/history.log
```

PVC 进入 `Bound` 后，NFS 导出下应出现对应子目录。PV 名称由系统生成，`spec.csi.driver` 为 `nfs.csi.k8s.io`。

## 清理边界

先删除 Pod，再删除 PVC：

```bash
kubectl delete po nfs-csi-writer
kubectl delete pvc nfs-csi-data
kubectl get pv
```

由于 StorageClass 使用 `Retain`，PV 会进入 `Released`，NFS 子目录和数据仍然存在。确认数据已经备份或不再需要后，管理员再处理 PV 对象和服务端目录；仅删除 PV 对象不会清理 `Retain` 策略下的 NFS 数据。

## 参考

- [CSI 卷](https://kubernetes.io/docs/concepts/storage/volumes/#csi)
- [持久卷回收](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#reclaiming)
