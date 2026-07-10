# Secret 使用与安全

Secret 可以作为环境变量、只读卷或镜像拉取凭据提供给 Pod。选择注入方式时，既要考虑应用接口，也要控制凭据暴露范围和轮换行为。

## 环境变量与卷

下面的 Pod 同时演示按键注入环境变量和投射 Secret 文件。它引用上一页创建的 `app-secret`：

```yaml [secret-consumer.yaml]
apiVersion: v1
kind: Pod
metadata:
  name: secret-consumer
spec:
  restartPolicy: Never
  containers:
    - name: app
      image: busybox:1.38
      command:
        - sh
        - -c
        - test -s /run/secrets/password && sleep 3600
      env:
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: app-secret
              key: username
      volumeMounts:
        - name: credentials
          mountPath: /run/secrets
          readOnly: true
  volumes:
    - name: credentials
      secret:
        secretName: app-secret
        defaultMode: 0400
        items:
          - key: password
            path: password
```

```bash
kubectl create -f secret-consumer.yaml
kubectl describe pod secret-consumer
```

环境变量适合只在进程启动时读取的配置，但可能被应用调试输出、错误报告或子进程继承。卷文件更便于限制路径和权限，也能接收 Secret 后续更新，通常更适合支持文件重载的应用。

> [!CAUTION]
> 不要用 `kubectl exec ... -- env`、`cat` 或调试日志展示真实 Secret。排查时优先检查键是否存在、文件元数据和事件，不输出内容本身。

## 更新与轮换

Secret 卷与 ConfigMap 卷一样由 kubelet 最终一致地更新。具体延迟取决于 kubelet 同步周期和变更检测缓存策略，应用还必须重新读取文件才会使用新值。

以下路径不会在运行中自动变化：

- 通过 `env` 或 `envFrom` 注入的环境变量，需要重建 Pod。
- 使用 `subPath` 挂载的单个 Secret 文件，需要重建 Pod。
- 已读取到进程内存中的凭据，需要应用自身实现重载或重连。

轮换流程通常是先更新或创建新版本 Secret，再滚动更新工作负载，验证新凭据生效后撤销旧凭据。对证书、数据库密码和外部 API Token，还要协调凭据签发方的有效期与双凭据过渡窗口。

## 可选引用

Secret 对象或键默认必须存在，否则 Pod 无法正常启动。确实允许缺省配置时可以设置 `optional: true`：

```yaml{5-7}
env:
  - name: OPTIONAL_TOKEN
    valueFrom:
      secretKeyRef:
        name: optional-secret
        key: token
        optional: true
```

这只是用于说明字段关系的 Pod 片段，不是完整资源。缺失值会让环境变量不出现，应用必须明确处理这种状态；必需凭据不应设为可选。

## 不可变 Secret

不需要原地轮换的数据可以标记为不可变：

```yaml [immutable-secret.yaml]
apiVersion: v1
kind: Secret
metadata:
  name: immutable-secret
type: Opaque
immutable: true
stringData:
  token: <replace-before-create>
```

```bash
kubectl create -f immutable-secret.yaml
```

不可变 Secret 能避免误更新，并在大量挂载场景下降低 API Server watch 压力。一旦设为不可变，就不能恢复为可变对象，也不能修改数据，只能用新名称创建替代对象并更新引用。

## 集群侧保护

Secret 的安全性依赖多层控制：

- 为 API Server 配置 Secret 静态加密，并制定加密密钥轮换流程。
- 使用 RBAC 限制 `get`、`list` 和 `watch`；允许读取 Pod 的主体还可能通过创建 Pod 间接读取该命名空间内可引用的 Secret。
- 将工作负载分布到合理的命名空间和 ServiceAccount，避免所有应用共享一组凭据。
- 只向容器投射所需键，不把高权限凭据挂载给不需要它的 Sidecar 或调试容器。
- 对外部系统优先使用短期、可撤销、权限最小的凭据。
- 需要集中托管时，评估 Secrets Store CSI Driver 或外部 Secret 控制器；这些组件不属于 Kubernetes 核心 Secret API。

Secret 挂载到 Pod 后，kubelet 只会获取该 Pod 实际引用的 Secret，并在节点上使用 `tmpfs` 保存 Secret 数据。不过，节点或容器运行时被攻破后仍可能泄漏挂载内容，因此节点安全与工作负载隔离仍然必要。

## 版本管理与恢复

Kubernetes 没有面向单个 ConfigMap 或 Secret 的内置版本历史。`kubectl get -o yaml` 只能导出当前对象，并会包含服务端元数据；对于 Secret，导出内容仍然只是可解码的 Base64 数据。

非敏感 ConfigMap 可以把声明式清单作为配置来源纳入 Git。Secret 应使用加密后清单、外部密钥系统或集群备份方案，不能把明文或普通 Base64 清单提交到仓库。恢复前还要确认命名空间、RBAC、加密密钥和外部凭据仍然有效。

## 排查路径

```bash
kubectl get secret
kubectl describe secret app-secret
kubectl describe pod secret-consumer
kubectl get events --sort-by=.metadata.creationTimestamp
```

常见状态及检查方向：

| 现象                           | 检查方向                              |
|------------------------------|-----------------------------------|
| `CreateContainerConfigError` | Secret 名称、键名、命名空间、是否被删除           |
| `ContainerCreating`          | 卷投射事件、`items` 键、文件路径和节点状态         |
| `ImagePullBackOff`           | `imagePullSecrets`、仓库地址、账号权限和镜像路径 |
| 凭据更新后仍使用旧值                   | 环境变量、`subPath`、应用缓存和连接池           |
| Secret 无法修改                  | `immutable` 是否为 `true`            |
