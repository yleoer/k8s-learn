# Pod 健康检查与探针配置

Kubernetes 通过 kubelet 对容器执行健康探针：`startupProbe`、`livenessProbe` 和 `readinessProbe`。它们检查的是不同层面的问题，失败后的处理方式也不同。

## 三种探针

| 探针               | 解决的问题      | 失败后的结果                             |
|------------------|------------|------------------------------------|
| `startupProbe`   | 应用是否已经完成启动 | 失败超过阈值后重启容器                        |
| `livenessProbe`  | 应用是否仍然存活   | 失败超过阈值后重启容器                        |
| `readinessProbe` | 应用是否可以接收流量 | 失败后标记为 NotReady，Service 不再将其作为可用后端 |

慢启动应用应优先配置 startupProbe。长期运行的服务建议配置 readinessProbe。livenessProbe 只检查应用是否需要重启，不应依赖数据库、缓存或第三方外部接口。

## startupProbe 完整示例

`startupProbe` 用于保护启动较慢的应用。在 startupProbe 成功之前，livenessProbe 和 readinessProbe 不会按运行期逻辑影响容器。

```yaml{11-16} [startup-probe-demo.yaml]
apiVersion: v1
kind: Pod
metadata:
  name: startup-probe-demo
spec:
  containers:
    - name: nginx
      image: nginx:1.31-alpine
      ports:
        - containerPort: 80
      startupProbe:
        httpGet:
          path: /
          port: 80
        periodSeconds: 5
        failureThreshold: 12
```

该配置表示 kubelet 每 5 秒检查一次 Nginx 首页，最多允许连续失败 12 次。换算后，应用大约有 60 秒启动窗口：

```text
5 秒 * 12 = 60 秒
```

创建并查看：

```bash
kubectl create -f startup-probe-demo.yaml
kubectl get pod startup-probe-demo
kubectl describe pod startup-probe-demo
```

## livenessProbe 完整示例

`livenessProbe` 用于判断容器是否仍然存活。探针连续失败后，kubelet 会重启容器。

```yaml{11-18} [liveness-probe-demo.yaml]
apiVersion: v1
kind: Pod
metadata:
  name: liveness-probe-demo
spec:
  containers:
    - name: nginx
      image: nginx:1.31-alpine
      ports:
        - containerPort: 80
      livenessProbe:
        httpGet:
          path: /
          port: 80
        initialDelaySeconds: 10
        periodSeconds: 10
        timeoutSeconds: 2
        failureThreshold: 3
```

该配置表示容器启动 10 秒后开始检查，每 10 秒检查一次。如果连续失败 3 次，kubelet 会重启容器。livenessProbe 应保持相对保守，避免因为外部依赖短暂异常导致容器反复重启。

创建并查看：

```bash
kubectl create -f liveness-probe-demo.yaml
kubectl get pod liveness-probe-demo
kubectl describe pod liveness-probe-demo
```

## readinessProbe 完整示例

`readinessProbe` 用于判断 Pod 是否可以接收业务流量。探针失败后，Pod 不会被重启，但会变为 NotReady，Service 不再将其作为可用后端。

```yaml{13-21} [readiness-probe-demo.yaml]
apiVersion: v1
kind: Pod
metadata:
  name: readiness-probe-demo
  labels:
    app: readiness-probe-demo
spec:
  containers:
    - name: nginx
      image: nginx:1.31-alpine
      ports:
        - containerPort: 80
      readinessProbe:
        httpGet:
          path: /
          port: 80
        initialDelaySeconds: 5
        periodSeconds: 5
        timeoutSeconds: 2
        successThreshold: 1
        failureThreshold: 2
```

该配置表示容器启动 5 秒后开始检查，每 5 秒检查一次。如果连续失败 2 次，Pod 会变为 NotReady；探针恢复成功后，Pod 才会重新具备接收流量的条件。

创建并查看：

```bash
kubectl create -f readiness-probe-demo.yaml
kubectl get pod readiness-probe-demo
kubectl describe pod readiness-probe-demo
```

## 四种检查方式

| 方式          | 说明                         | 适用场景             |
|-------------|----------------------------|------------------|
| `exec`      | 在容器内执行命令，退出码为 0 表示成功       | 自定义脚本、本地文件或进程检查  |
| `tcpSocket` | 对指定端口建立 TCP 连接             | 只能判断端口是否可连接      |
| `httpGet`   | 发送 HTTP GET 请求，根据状态码判断     | Web 服务、HTTP 健康接口 |
| `grpc`      | 使用 gRPC Health Checking 协议 | gRPC 服务健康检查      |

HTTP 方式的完整写法见上文 readinessProbe 示例。

TCP liveness 示例：

```yaml{11-16} [tcp-liveness-demo.yaml]
apiVersion: v1
kind: Pod
metadata:
  name: tcp-liveness-demo
spec:
  containers:
    - name: nginx
      image: nginx:1.31-alpine
      ports:
        - containerPort: 80
      livenessProbe:
        tcpSocket:
          port: 80
        initialDelaySeconds: 10
        periodSeconds: 10
        failureThreshold: 3
```

exec 示例：

```yaml{13-19} [exec-liveness-demo.yaml]
apiVersion: v1
kind: Pod
metadata:
  name: exec-liveness-demo
spec:
  containers:
    - name: app
      image: busybox:1.38
      command:
        - sh
        - -c
        - touch /tmp/healthy; sleep 3600
      livenessProbe:
        exec:
          command:
            - sh
            - -c
            - test -f /tmp/healthy
        periodSeconds: 10
```

gRPC 示例：

```yaml{13-16} [grpc-readiness-demo.yaml]
apiVersion: v1
kind: Pod
metadata:
  name: grpc-readiness-demo
spec:
  containers:
    - name: agnhost
      image: registry.k8s.io/e2e-test-images/agnhost:2.45
      args:
        - grpc-health-checking
      ports:
        - containerPort: 5000
      readinessProbe:
        grpc:
          port: 5000
        periodSeconds: 5
```

gRPC 探针要求应用实现标准的 gRPC Health Checking 协议，响应为 `SERVING` 时视为检查通过。示例中 `agnhost grpc-health-checking` 默认监听 `5000` 端口。

## 时间参数

| 字段                    | 默认值  | 含义               |
|-----------------------|------|------------------|
| `initialDelaySeconds` | `0`  | 容器启动后等待多久开始第一次检查 |
| `periodSeconds`       | `10` | 每隔多久执行一次检查       |
| `timeoutSeconds`      | `1`  | 单次检查最多等待多久       |
| `failureThreshold`    | `3`  | 连续失败多少次才判定失败     |
| `successThreshold`    | `1`  | 连续成功多少次才判定为成功    |

失败判定可粗略估算为：

```text
initialDelaySeconds + periodSeconds * failureThreshold
```

readinessProbe 可以将 `successThreshold` 设为大于 `1`，要求连续成功多次后才恢复 Ready 状态。livenessProbe 和 startupProbe 的 `successThreshold` 必须为 `1`。
