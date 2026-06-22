# Pod 环境变量与内置元数据

Pod 可以通过 `env` 为容器注入环境变量。环境变量既可以填写固定值，也可以通过 `fieldRef` 引用 Pod 自身的元数据字段，这种方式属于 downward API 的常见用法。

## 固定值环境变量

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: env-demo
spec:
  containers:
    - name: nginx
      image: nginx:stable-alpine
      env:
        - name: ENV
          value: test
        - name: APP_NAME
          value: nginx
```

查看环境变量：

```bash
kubectl create -f env-demo.yaml
kubectl get po env-demo -owide
kubectl exec -it env-demo -- env
```

## 使用 fieldRef 引用 Pod 字段

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: fieldref-demo
  labels:
    app: fieldref-demo
spec:
  containers:
    - name: nginx
      image: nginx:stable-alpine
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
kubectl get po fieldref-demo -owide
kubectl exec -it fieldref-demo -- env | grep POD
```

环境变量在容器启动时注入，Pod 运行期间如果元数据发生变化，已注入的环境变量不会自动更新。

## 常用内置字段

| fieldPath | 注入内容 |
| --- | --- |
| `metadata.name` | Pod 名称 |
| `metadata.namespace` | Pod 所在 Namespace |
| `metadata.uid` | Pod UID |
| `metadata.labels['app']` | 指定 label 值 |
| `metadata.annotations['trace-id']` | 指定 annotation 值 |
| `spec.nodeName` | Pod 所在节点名称 |
| `spec.serviceAccountName` | Pod 使用的 ServiceAccount |
| `status.hostIP` | 节点 IP |
| `status.podIP` | Pod IP |

## metadata、spec 与 status

Pod 的常用信息分布在三个区域。

| 区域 | 常用字段 | 说明 |
| --- | --- | --- |
| `metadata` | `name`、`namespace`、`labels`、`annotations` | 标识和描述 Pod |
| `spec` | `nodeName`、`containers`、`restartPolicy`、`volumes` | 描述期望运行状态 |
| `status` | `phase`、`podIP`、`hostIP`、`conditions` | 描述实际运行状态 |

查看完整 YAML：

```bash
kubectl get pod <pod-name> -o yaml
```

使用 jsonpath 获取指定字段：

```bash
kubectl get pod <pod-name> -o jsonpath='{.status.podIP}'
kubectl get pod <pod-name> -o jsonpath='{.spec.nodeName}'
kubectl get pod <pod-name> -o jsonpath='{.status.containerStatuses[*].restartCount}'
```

常见 conditions 包括 `PodScheduled`、`Initialized`、`ContainersReady` 和 `Ready`。其中 `Ready` 直接影响 Pod 是否可以被 Service 接入流量。
