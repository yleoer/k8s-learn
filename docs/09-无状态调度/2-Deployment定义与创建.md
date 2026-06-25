# Deployment 定义与创建

Deployment 的核心配置集中在 `metadata`、`spec.selector` 和 `spec.template`。其中 `spec.template` 是 Pod 模板，决定了 Deployment 创建的 Pod 的具体形态。

只要 Pod 模板发生变化，Deployment 就会触发新版本发布。仅修改 `replicas` 不会创建新版本，因为副本数变化不属于 Pod 模板变化。

## 最小示例

下面是一个最小可用 Deployment：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deploy
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx-deploy
  template:
    metadata:
      labels:
        app: nginx-deploy
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
          ports:
            - containerPort: 80
```

创建并查看：

```bash
kubectl create -f nginx-deploy.yaml
kubectl get deploy
kubectl get rs
kubectl get po -l app=nginx-deploy -o wide
```

也可以用命令快速生成模板：

```bash
kubectl create deploy nginx-deploy --image=nginx:1.25 --dry-run=client -o yaml
```

生成的模板通常还需要补充 `replicas`、标签、端口、资源限制、探针和更新策略，才能接近生产可用配置。

## 基础字段

| 字段 | 是否必选 | 说明 |
| --- | --- | --- |
| `apiVersion` | 是 | Deployment 使用 `apps/v1` |
| `kind` | 是 | 资源类型，固定为 `Deployment` |
| `metadata.name` | 是 | Deployment 名称，同一 Namespace 内唯一 |
| `spec.replicas` | 否 | 期望副本数，默认值为 1 |
| `spec.selector` | 是 | 用于匹配下层 Pod 的标签选择器 |
| `spec.template` | 是 | Pod 模板 |
| `spec.template.metadata.labels` | 是 | Pod 标签，必须能被 selector 匹配 |
| `spec.template.spec.containers` | 是 | 容器列表 |

Deployment 的 `spec.selector.matchLabels` 必须匹配 Pod 模板中的标签：

```yaml
selector:
  matchLabels:
    app: nginx
template:
  metadata:
    labels:
      app: nginx
```

如果二者不匹配，创建时会失败。创建成功后，`spec.selector` 通常不可修改，因此前期应规划好稳定标签。

## 常用增强配置

生产中常见的 Deployment 还会补充资源限制、健康检查、更新策略和历史版本保留：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 3
  revisionHistoryLimit: 5
  selector:
    matchLabels:
      app: nginx
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
          ports:
            - name: http
              containerPort: 80
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
          readinessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 15
            periodSeconds: 20
```

生产中的 Deployment 不应只包含镜像和副本数，还应逐步补齐 `resources`、`readinessProbe`、`livenessProbe`、`startupProbe`、`strategy`、`revisionHistoryLimit` 以及优雅退出配置。

## 创建过程

创建 Deployment 后，Pod 并非由用户直接创建。Kubernetes 会通过控制器链路逐层生成资源：

| 步骤 | 组件 | 行为 |
| --- | --- | --- |
| 1 | APIServer | 接收 Deployment YAML 并保存到 etcd |
| 2 | Deployment Controller | 发现新 Deployment，创建对应 ReplicaSet |
| 3 | ReplicaSet Controller | 根据 `replicas` 创建 Pod |
| 4 | Scheduler | 为 Pending 状态的 Pod 选择节点 |
| 5 | kubelet | 在目标节点拉取镜像并启动容器 |
| 6 | kubelet | 上报 Pod 状态，控制器继续对齐期望状态 |

Pod 名称通常包含 ReplicaSet 名称前缀，例如：

```text
nginx-deploy-596cdb74d9-2s4kc
```

其中 `nginx-deploy-596cdb74d9` 是 ReplicaSet 名称，最后一段是 Pod 随机后缀。

## 状态字段

查看 Deployment：

```bash
kubectl get deploy nginx-deploy
```

示例输出：

```text
NAME           READY   UP-TO-DATE   AVAILABLE   AGE
nginx-deploy   3/3     3            3           17s
```

| 字段 | 说明 |
| --- | --- |
| `READY` | 就绪副本数与期望副本数，例如 `3/3` |
| `UP-TO-DATE` | 已经更新到最新模板版本的副本数 |
| `AVAILABLE` | 可用副本数，通常表示已就绪并满足最小可用时间 |
| `AGE` | Deployment 创建时长 |

查看发布进度：

```bash
kubectl rollout status deploy nginx-deploy
```

查看完整状态和事件：

```bash
kubectl get deploy nginx-deploy -o yaml
kubectl describe deploy nginx-deploy
```

如果 Deployment 显示未就绪，可以继续查看下层资源：

```bash
kubectl get rs -l app=nginx-deploy
kubectl get po -l app=nginx-deploy
kubectl describe po <pod-name>
```

Deployment 状态用于判断发布整体是否成功，Pod 状态用于定位具体失败原因。排查时应从 Deployment 向下逐层展开。
