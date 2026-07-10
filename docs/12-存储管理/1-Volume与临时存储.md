# Volume 与临时存储

容器可写层通常随容器替换而丢失，同一 Pod 中不同容器的文件系统也彼此隔离。Volume 在 Pod 级声明数据源，每个容器再独立决定挂载路径和读写方式。

## Volume 结构

`spec.volumes` 定义卷，`spec.containers[*].volumeMounts` 通过相同名称引用卷。一个卷可以挂载到同一 Pod 的多个容器，也可以在不同容器中使用不同路径。

常见数据源包括：

| 数据源                                            | 生命周期与用途                           |
|------------------------------------------------|-----------------------------------|
| `emptyDir`                                     | Pod 位于节点期间存在，用于缓存、临时计算和同一 Pod 内共享 |
| `hostPath`                                     | 直接访问 Pod 所在节点文件系统，主要用于受控的节点级组件    |
| `configMap`、`secret`、`projected`、`downwardAPI` | 把 API 数据投射为文件，不用于通用持久化            |
| `nfs`                                          | 挂载已有 NFS 导出，数据独立于 Pod 生命周期        |
| `persistentVolumeClaim`                        | 通过 PVC 使用静态或动态供给的持久卷              |
| `csi`                                          | 由 CSI 驱动提供卷；长期数据通常仍通过 PV/PVC 管理   |
| `ephemeral`                                    | 从 PVC 模板创建与 Pod 生命周期绑定的通用临时卷      |

Volume 不能嵌套挂载到另一个 Volume 中。需要只挂载卷内子目录时可使用 `subPath`，但 ConfigMap 和 Secret 的 `subPath` 挂载不会接收自动更新。

临时卷的生命周期与 Pod 绑定，但实现路径不同：`emptyDir` 和 API 数据投射由 kubelet 管理；CSI 临时卷由支持该能力的 CSI 驱动直接提供；通用临时卷通过 `ephemeral.volumeClaimTemplate` 创建 PVC，因此可以复用 StorageClass 的动态供给、容量和拓扑能力。通用临时卷对应的 PVC 会随 Pod 删除，后端卷是否保留仍取决于 PV 回收策略。

## emptyDir

`emptyDir` 在 Pod 被分配到节点时创建，初始为空。容器崩溃或重启不会删除数据；Pod 被移出节点或删除时，数据会永久删除，因此它不是持久卷。

下面的 Pod 让初始化容器写入网页文件，再由 Nginx 读取同一个 `emptyDir`：

```yaml [emptydir-pod.yaml]
apiVersion: v1
kind: Pod
metadata:
  name: emptydir-demo
spec:
  initContainers:
    - name: prepare-content
      image: busybox:1.38
      command: ["sh", "-c", "printf 'shared from emptyDir\n' > /work/index.html"]
      volumeMounts:
        - name: work
          mountPath: /work
  containers:
    - name: nginx
      image: nginx:1.31-alpine
      ports:
        - name: http
          containerPort: 80
      volumeMounts:
        - name: work
          mountPath: /usr/share/nginx/html
    - name: reader
      image: busybox:1.38
      command: ["sh", "-c", "while true; do cat /work/index.html; sleep 30; done"]
      volumeMounts:
        - name: work
          mountPath: /work
          readOnly: true
  volumes:
    - name: work
      emptyDir:
        sizeLimit: 256Mi
```

```bash
kubectl create -f emptydir-pod.yaml
kubectl exec emptydir-demo -c reader -- cat /work/index.html
```

默认介质来自节点上承载 kubelet 根目录的文件系统，使用量计入节点本地临时存储。`sizeLimit` 限制卷容量，但节点日志、镜像层等其他数据也会消耗同一文件系统，卷可能在到达声明上限前就因节点空间不足而不可用。超出本地临时存储限制或触发节点磁盘压力时，Pod 可能被驱逐，并不会变成 `Completed`。

### 内存介质

将 `medium` 设置为 `Memory` 会创建 tmpfs：

```yaml{4,5}
volumes:
  - name: cache
    emptyDir:
      medium: Memory
      sizeLimit: 128Mi
```

这是用于说明字段关系的片段，不是完整 Pod 清单。tmpfs 中的数据计入写入它的容器内存用量；未设置 `sizeLimit` 时，卷本身按节点可分配内存确定大小，但实际可用量还会受 Pod 或容器内存限制和节点剩余内存约束。使用内存卷时必须同时规划内存请求和限制，避免内存数据挤占应用堆并触发 OOM。

## 本地临时存储资源

磁盘介质的 `emptyDir`、容器可写层和 Pod 日志共同消耗节点本地临时存储。容器可以声明 `ephemeral-storage` 请求与限制，下面只是容器资源字段片段：

```yaml
resources:
  requests:
    ephemeral-storage: 256Mi
  limits:
    ephemeral-storage: 1Gi
```

调度器使用请求值判断节点是否可容纳 Pod；kubelet 依据实际用量、容器限制、Pod 汇总限制和节点磁盘压力决定是否驱逐 Pod。`emptyDir.sizeLimit` 只限制对应卷，不能替代容器的 `ephemeral-storage` 限制；内存介质的 `emptyDir` 计入内存而不是本地临时存储。

> [!CAUTION]
> 容量单位大小写会改变数量级，例如 `400m` 表示 0.4 字节而不是 400 MiB；本地临时存储应使用 `Mi`、`Gi` 等二进制单位，或 `M`、`G` 等十进制单位。

## hostPath

`hostPath` 把节点上的文件或目录直接挂载进 Pod。它会把工作负载绑定到节点本地状态，并可能暴露 kubelet 凭据、容器运行时套接字或宿主机系统文件。

> [!WARNING]
> 普通业务 Pod 应避免使用 `hostPath`。确有节点日志采集、设备访问等节点级需求时，应限制允许路径、使用只读挂载、约束可运行的节点，并通过准入策略阻止不受信任的工作负载自行声明主机路径。

只读查看节点日志目录的完整示例：

```yaml [hostpath-pod.yaml]
apiVersion: v1
kind: Pod
metadata:
  name: hostpath-log-reader
spec:
  nodeSelector:
    kubernetes.io/os: linux
  restartPolicy: Never
  containers:
    - name: reader
      image: busybox:1.38
      command: ["sh", "-c", "ls -la /host-logs && sleep 3600"]
      volumeMounts:
        - name: host-logs
          mountPath: /host-logs
          readOnly: true
  volumes:
    - name: host-logs
      hostPath:
        path: /var/log
        type: Directory
```

```bash
kubectl create -f hostpath-pod.yaml
```

`hostPath.type` 可以在挂载前检查对象类型：

| 类型                         | 行为                              |
|----------------------------|---------------------------------|
| 空字符串                       | 不检查，兼容旧清单                       |
| `DirectoryOrCreate`        | 目录不存在时以 kubelet 身份创建，权限为 `0755` |
| `Directory`                | 要求目录已经存在                        |
| `FileOrCreate`             | 文件不存在时创建空文件，权限为 `0644`；不会创建父目录  |
| `File`                     | 要求文件已经存在                        |
| `Socket`                   | 要求 Unix Socket 已经存在             |
| `CharDevice`、`BlockDevice` | 要求对应 Linux 设备已经存在               |

`hostPath` 用量不计入 Pod 的本地临时存储用量，需要单独监控节点磁盘。节点间文件不同还可能导致同一 Pod 模板表现不一致；需要受调度器感知的节点本地持久存储时，应使用带 `nodeAffinity` 的 `local` PV。

## 直接挂载 NFS

已有 NFS 导出可以直接写入 Pod：

```yaml [nfs-direct-pod.yaml]
apiVersion: v1
kind: Pod
metadata:
  name: nfs-direct-demo
spec:
  containers:
    - name: nginx
      image: nginx:1.31-alpine
      volumeMounts:
        - name: content
          mountPath: /usr/share/nginx/html
  volumes:
    - name: content
      nfs:
        server: <nfs-server-ip>
        path: /srv/nfs/k8s/direct
        readOnly: false
```

```bash
kubectl create -f nfs-direct-pod.yaml
```

NFS 服务器和导出目录必须提前存在，所有可能运行 Pod 的节点还要安装 NFS 客户端工具。Pod 的 `nfs` 数据源不能声明挂载参数；需要 `nfsvers` 等选项时，可通过 PV 的 `mountOptions` 或 StorageClass 配置。

直接卷把后端地址写入工作负载，不利于复用和迁移。长期数据更适合由 PV/PVC 表达，批量按需创建目录则使用 CSI 与 StorageClass。
