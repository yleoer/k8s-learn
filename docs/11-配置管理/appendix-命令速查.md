# 配置管理速查

本章整理 ConfigMap、Secret 与配置注入的常用操作。配置对象保存数据并被工作负载引用，但不会自动提供访问控制、加密或业务配置兼容性。

## 关键对象与边界

| 对象 | 作用 | 不负责 |
| --- | --- | --- |
| ConfigMap | 保存非敏感配置 | 存储密码或私钥 |
| Secret | 保存敏感数据引用 | 自动加密全部访问路径 |
| env / volume | 将配置注入容器 | 自动让应用重新加载 |

## 命令速查

### 创建与查看

```bash
kubectl create -f app-config.yaml
kubectl create -f app-secret.yaml
kubectl get cm
kubectl get secret
kubectl describe cm <configmap-name>
kubectl describe secret <secret-name>
```

### 命令式 Secret

```bash
kubectl create secret generic database-credentials \
  --from-literal=username='<database-user>' \
  --from-literal=password='<database-password>'
kubectl create secret tls ingress-tls \
  --cert=tls.crt \
  --key=tls.key
kubectl create secret docker-registry registry-credentials \
  --docker-server='<registry.example.com>'
```

避免在命令行直接传递真实密码；示例中的 `--from-literal` 仅用于解释参数，真实凭据优先使用受控文件、外部密钥系统或加密配置。

## 配置速查

| 配置 | 检查重点 |
| --- | --- |
| `data` 与 `stringData` | 前者为 Base64 编码值，后者写入时合并到 `data` |
| 环境变量注入 | 需要重建 Pod 才能读取新值 |
| 卷投射 | kubelet 会同步文件，但应用是否热加载由应用决定 |
| immutable | 阻止原对象更新，适合版本化配置 |

## 排查索引

| 现象 | 优先检查 | 正文 |
| --- | --- | --- |
| Pod 无法启动 | ConfigMap、Secret 名称与键是否存在 | [配置注入与更新](./2-配置注入与更新.md) |
| 镜像拉取失败 | `imagePullSecrets` 的类型、命名空间与仓库路径 | [Secret 资源](./3-Secret资源.md) |
| 更新未生效 | 注入方式、应用重载和 Pod 重建 | [配置注入与更新](./2-配置注入与更新.md) |

## 关联页面

- [ConfigMap 资源](./1-ConfigMap资源.md)
- [Secret 使用与安全](./4-Secret使用与安全.md)

## 参考

- [ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Secret](https://kubernetes.io/docs/concepts/configuration/secret/)
