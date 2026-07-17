# Helm

RBAC 提供发布主体的权限边界后，Helm 将一组 Kubernetes 清单、默认值和发布记录组织为可版本化的 Chart 与 Release。它适合管理参数化的应用资源，但不替代 Git 审核、镜像供应链和集群准入控制。

本章以当前 Helm 4 文档的 OCI 工作流、Chart 模板和 Release 生命周期为主线。旧草稿中的 Helm Museum 条目不再保留；传统 HTTP Chart 仓库仍受支持，但新仓库设计优先采用 OCI 分发。

## 共同约定

Chart 的版本、应用镜像 tag 和依赖版本必须明确固定。生产发布先执行渲染与差异审查，再通过受限 ServiceAccount 执行；不要把密码、私钥或 kubeconfig 写入 `values.yaml`。

## 参考

- [Helm 快速开始指南](https://helm.sh/docs/intro/quickstart/)
- [使用 OCI 镜像仓库](https://helm.sh/docs/topics/registries/)
