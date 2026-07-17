# Pod 环境变量与内置元数据

Pod 可以通过 `env` 为容器注入环境变量。环境变量既可以填写固定值，也可以通过 `fieldRef` 引用 Pod 自身的元数据字段，或通过 `resourceFieldRef` 引用容器的资源配置。环境变量与 downwardAPI 卷合称 downward API，让应用在不访问 Kubernetes API 的情况下获取自身信息。

## 固定值环境变量

```yaml{9-13} [env-demo.yaml]
apiVersion: v1
kind: Pod
metadata:
  name: env-demo
spec:
  containers:
    - name: nginx
      image: nginx:1.31-alpine
      env:
        - name: ENV
          value: test
        - name: APP_NAME
          value: nginx
```

查看环境变量：

```bash
kubectl create -f env-demo.yaml
kubectl get po env-demo -o wide
kubectl exec -it env-demo -- env
```

## 使用 fieldRef 引用 Pod 字段

```yaml{11-27} [fieldref-demo.yaml]
apiVersion: v1
kind: Pod
metadata:
  name: fieldref-demo
  labels:
    app: fieldref-demo
spec:
  containers:
    - name: nginx
      image: nginx:1.31-alpine
      env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: POD_NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
```

创建后验证：

```bash
kubectl create -f fieldref-demo.yaml
kubectl get po fieldref-demo -o wide
kubectl exec -it fieldref-demo -- env | grep POD
```

环境变量在容器启动时注入，Pod 运行期间如果元数据发生变化，已注入的环境变量不会自动更新；与 downwardAPI 卷的更新差异见下文。

## 常用内置字段

`fieldRef` 可引用的字段分为三类，部分字段只能用于环境变量或只能用于 downwardAPI 卷：

| fieldPath                          | 注入内容                   | 可用位置   |
|------------------------------------|------------------------|--------|
| `metadata.name`                    | Pod 名称                 | 环境变量与卷 |
| `metadata.namespace`               | Pod 所在 Namespace       | 环境变量与卷 |
| `metadata.uid`                     | Pod UID                | 环境变量与卷 |
| `metadata.labels['app']`           | 指定 label 值             | 环境变量与卷 |
| `metadata.annotations['trace-id']` | 指定 annotation 值        | 环境变量与卷 |
| `metadata.labels`                  | 全部标签，每行一条              | 仅卷     |
| `metadata.annotations`             | 全部注解，每行一条              | 仅卷     |
| `spec.nodeName`                    | Pod 所在节点名称             | 仅环境变量  |
| `spec.serviceAccountName`          | Pod 使用的 ServiceAccount | 仅环境变量  |
| `status.hostIP`                    | 节点 IP                  | 仅环境变量  |
| `status.podIP`                     | Pod IP                 | 仅环境变量  |

## 使用 resourceFieldRef 引用资源值

`resourceFieldRef` 把容器的 CPU、内存等资源配置注入为环境变量，可引用 `requests.cpu`、`limits.cpu`、`requests.memory`、`limits.memory`，以及 `ephemeral-storage` 和 `hugepages-*` 的对应字段：

```yaml{17-29} [resourcefieldref-demo.yaml]
apiVersion: v1
kind: Pod
metadata:
  name: resourcefieldref-demo
spec:
  containers:
    - name: app
      image: busybox:1.38
      command: ["sh", "-c", "env | grep MY_; sleep 3600"]
      resources:
        requests:
          cpu: 125m
          memory: 32Mi
        limits:
          cpu: 250m
          memory: 64Mi
      env:
        - name: MY_CPU_LIMIT
          valueFrom:
            resourceFieldRef:
              containerName: app
              resource: limits.cpu
              divisor: 1m
        - name: MY_MEM_LIMIT
          valueFrom:
            resourceFieldRef:
              containerName: app
              resource: limits.memory
              divisor: 1Mi
```

创建后验证注入结果：

```bash
kubectl create -f resourcefieldref-demo.yaml
kubectl logs resourcefieldref-demo
```

`divisor` 决定数值单位，默认值为 1，表示 CPU 按核、内存按字节输出，且 CPU 会向上取整——`125m` 在默认 divisor 下输出 `1`。需要毫核或 MiB 时必须显式设置 `divisor: 1m` 或 `1Mi`。上面示例中 `MY_CPU_LIMIT` 输出 `250`，`MY_MEM_LIMIT` 输出 `64`。

容器没有设置 limits 时，kubelet 会回退注入节点可分配资源量（node allocatable），而不是报错。应用把这类值当作并发度或缓存大小依据时，需要意识到未设 limits 时拿到的是整个节点的容量。

## downwardAPI 卷

downwardAPI 卷把元数据以文件形式挂载进容器，适合读取全部标签、注解，或为无法读环境变量的组件提供配置：

```yaml{15-27} [downwardapi-volume-demo.yaml]
apiVersion: v1
kind: Pod
metadata:
  name: downwardapi-volume-demo
  labels:
    app: downwardapi-volume-demo
    zone: zone-a
  annotations:
    build: "2"
spec:
  containers:
    - name: app
      image: busybox:1.38
      command: ["sh", "-c", "cat /etc/podinfo/labels; sleep 3600"]
      volumeMounts:
        - name: podinfo
          mountPath: /etc/podinfo
  volumes:
    - name: podinfo
      downwardAPI:
        items:
          - path: labels
            fieldRef:
              fieldPath: metadata.labels
          - path: annotations
            fieldRef:
              fieldPath: metadata.annotations
```

验证文件内容：

```bash
kubectl create -f downwardapi-volume-demo.yaml
kubectl exec downwardapi-volume-demo -- cat /etc/podinfo/labels
kubectl exec downwardapi-volume-demo -- cat /etc/podinfo/annotations
```

文件中每行一条 `key="value"` 记录。卷中也可以通过 `resourceFieldRef` 暴露资源值，此时 `containerName` 为必填字段。

环境变量与卷最重要的差异是更新行为：

- 环境变量在容器启动时注入，Pod 运行期间元数据变化不会更新已注入的值，除非容器重启。
- downwardAPI 卷通过符号链接原子刷新，标签和注解变化后文件内容会跟随更新；但以 `subPath` 方式挂载时不会收到更新。

需要感知运行期变化（例如运维中途打标签）的场景应使用卷；只在启动时读取一次的配置用环境变量即可。

## metadata、spec 与 status

Pod 的常用信息分布在三个区域。

| 区域         | 常用字段                                              | 说明        |
|------------|---------------------------------------------------|-----------|
| `metadata` | `name`、`namespace`、`labels`、`annotations`         | 标识和描述 Pod |
| `spec`     | `nodeName`、`containers`、`restartPolicy`、`volumes` | 描述期望运行状态  |
| `status`   | `phase`、`podIP`、`hostIP`、`conditions`             | 描述实际运行状态  |

查看完整 YAML：

```bash
kubectl get po <pod-name> -o yaml
```

使用 jsonpath 获取指定字段：

```bash
kubectl get po <pod-name> -o jsonpath='{.status.podIP}'
kubectl get po <pod-name> -o jsonpath='{.spec.nodeName}'
kubectl get po <pod-name> -o jsonpath='{.status.containerStatuses[*].restartCount}'
```

常见 conditions 包括 `PodScheduled`、`Initialized`、`ContainersReady` 和 `Ready`。其中 `Ready` 直接影响 Pod 是否可以被 Service 接入流量。

## 参考

- [Downward API](https://kubernetes.io/docs/concepts/workloads/pods/downward-api/)
- [通过环境变量向容器暴露 Pod 信息](https://kubernetes.io/docs/tasks/inject-data-application/environment-variable-expose-pod-information/)
- [通过文件向容器暴露 Pod 信息](https://kubernetes.io/docs/tasks/inject-data-application/downward-api-volume-expose-pod-information/)
