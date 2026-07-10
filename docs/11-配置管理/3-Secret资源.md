# Secret 资源

Secret 用于保存密码、令牌、密钥和证书等敏感数据，并通过受控引用提供给工作负载。Secret 比把凭据直接写进 Pod 清单或镜像更便于隔离和授权，但对象本身不会自动获得完整的机密保护。

## 安全边界

Secret 的 `data` 使用 Base64 编码，这只是传输格式，不是加密。能够读取 Secret API 对象的人可以解码全部内容；默认情况下，Secret 在 etcd 中也可能以未加密形式保存。

> [!WARNING]
> 不要把真实 Secret 清单、解码后的输出、Token、私钥或生产凭据提交到版本库。生产集群应启用 Secret 静态加密，使用最小权限 RBAC，并结合外部密钥系统或加密后的声明式配置管理方案。

单个 Secret 的大小上限为 1 MiB。创建大量小 Secret 同样会增加 API Server 和 kubelet 的内存压力。

## data 与 stringData

`data` 的值必须预先进行 Base64 编码；`stringData` 接受明文字符串，API Server 写入时会合并并转换到 `data`。同名键同时存在时，`stringData` 优先。

下面的清单只使用占位值，实际文件应保存在仓库外：

```yaml [app-secret.yaml]
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
type: Opaque
stringData:
  username: <database-user>
  password: <database-password>
```

```bash
kubectl create -f app-secret.yaml
kubectl get secret app-secret
kubectl describe secret app-secret
```

`kubectl describe` 默认只显示键名和长度。显式输出 YAML 或 JSON 会暴露可解码的 `data`，不应把结果写入日志或问题记录。

`stringData` 便于手写清单，但与 Server-Side Apply 配合不佳。持续交付场景更适合使用专用的 Secret 加密或外部密钥同步方案。

## 常用类型

| `type`                                | 用途与约束                                       |
|---------------------------------------|---------------------------------------------|
| `Opaque`                              | 任意用户数据，也是未指定类型时的默认值                         |
| `kubernetes.io/basic-auth`            | 基本认证，通常包含 `username` 和 `password`           |
| `kubernetes.io/ssh-auth`              | SSH 私钥，要求 `ssh-privatekey` 键                |
| `kubernetes.io/tls`                   | TLS 证书与私钥，要求 `tls.crt` 和 `tls.key`          |
| `kubernetes.io/dockerconfigjson`      | 镜像仓库认证，要求 `.dockerconfigjson` 键             |
| `bootstrap.kubernetes.io/token`       | kubeadm 等集群引导流程使用的 Bootstrap Token          |
| `kubernetes.io/service-account-token` | 旧式长期 ServiceAccount Token，不作为 Pod 凭据的推荐创建方式 |

Pod 访问 Kubernetes API 时应使用自动投射、短期且可轮换的 ServiceAccount Token，不应手工创建 `kubernetes.io/service-account-token` Secret 代替 TokenRequest 机制。

## 命令式创建

从字面量创建通用 Secret：

```bash
kubectl create secret generic database-credentials \
  --from-literal=username='<database-user>' \
  --from-literal=password='<database-password>'
```

命令参数可能进入 Shell 历史、进程列表或审计记录。真实凭据更适合从权限受控的本地文件读取：

```text [username.txt]
<database-user>
```

```text [password.txt]
<database-password>
```

```bash
kubectl create secret generic database-credentials-files \
  --from-file=username=username.txt \
  --from-file=password=password.txt
```

创建完成后应安全删除仓库外的临时明文文件，并确认终端记录和自动化日志没有泄漏内容。

## TLS Secret

先在仓库外准备证书和对应私钥，再创建 TLS Secret：

```bash
kubectl create secret tls ingress-tls \
  --cert=tls.crt \
  --key=tls.key
```

kubectl 会检查公钥证书与私钥是否匹配。Ingress 通过 `spec.tls[].secretName` 引用同一命名空间中的 Secret，具体用法见[Ingress TLS 配置](/10-服务发现/5-Ingress#tls-终止)。

## 镜像仓库 Secret

创建私有仓库凭据：

```bash
kubectl create secret docker-registry registry-credentials \
  --docker-server='<registry.example.com>' \
  --docker-username='<registry-user>' \
  --docker-password='<registry-password>'
```

Pod 通过 `imagePullSecrets` 引用：

```yaml [private-image-pod.yaml]
apiVersion: v1
kind: Pod
metadata:
  name: private-image-demo
spec:
  imagePullSecrets:
    - name: registry-credentials
  containers:
    - name: app
      image: <registry.example.com>/<namespace>/app:1.0.0
```

```bash
kubectl create -f private-image-pod.yaml
```

Secret 与 Pod 必须位于同一命名空间。出现 `ImagePullBackOff` 时，应检查 Secret 类型、仓库地址、凭据权限、镜像路径和 Pod 事件。
