# Helm 与 Release

Helm 客户端把 Chart 渲染成 Kubernetes 资源并创建或更新 Release。Chart 是可发布的软件包，Release 是该 Chart 在某个集群和命名空间中的一次安装记录；同一 Chart 可以有多个独立 Release。

Helm 不维护集群内常驻的 Tiller 组件。权限由运行 Helm 的 kubeconfig 或 in-cluster ServiceAccount 决定，因此 Helm 不能绕过 RBAC、ResourceQuota、准入控制或策略限制。

## 典型生命周期

```text
Chart + values -> helm template -> rendered manifests
                                  -> admission and RBAC
                                  -> Kubernetes resources
                                  -> Release revision history
```

`helm template` 只在本地渲染，不连接集群；`helm install` 创建新的 Release；`helm upgrade` 变更已有 Release；`helm rollback` 使用历史修订重新发布。渲染成功不意味着集群准入、镜像拉取或 Pod 就绪一定成功。

## 安装前验证

```bash
helm version
helm env
kubectl auth can-i create deploy -n <namespace>
kubectl auth can-i create svc -n <namespace>
```

Helm 客户端与 Kubernetes 的支持矩阵会随版本演进。部署前应使用当前 Helm 发布说明确认目标集群版本的支持范围，并在非生产环境验证 Chart。

## 参考

- [Helm 介绍](https://helm.sh/docs/intro/)
- [使用 Helm](https://helm.sh/docs/intro/using_helm/)
