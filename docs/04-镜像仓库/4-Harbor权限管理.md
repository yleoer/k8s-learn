# Harbor 权限管理

Harbor 通过项目、用户和角色控制镜像访问权限。企业环境中不建议共用 `admin`，应按团队和职责拆分。

## 权限体系

| 对象 | 作用 |
| --- | --- |
| 用户 | Harbor 登录账号 |
| 项目 | 镜像隔离单元，如 `base`、`backend`、`frontend` |
| 成员 | 用户加入项目后的身份 |
| 角色 | 决定成员在项目中的操作权限 |

## 常见角色

| 角色 | 权限范围 |
| --- | --- |
| 项目管理员 | 管理项目成员、镜像、复制、扫描等配置 |
| 维护人员 | 维护镜像和仓库配置，不负责全局管理 |
| 开发人员 | 推送和拉取镜像，适合 CI/CD 或开发者 |
| 访客 | 只读，适合测试、运维或只需拉取的用户 |
| 受限访客 | 更严格的只读访问 |

## 项目划分建议

按业务：

```text
mall
payment
user-center
```

按环境：

```text
dev
test
prod
```

按镜像类型：

```text
base         # 基础镜像（nginx、redis 等）
middleware   # 中间件镜像
business     # 业务服务镜像
```

小团队可按业务划分；大团队建议结合组织、业务线和环境多层设计。

## 创建用户

在 Harbor Web 控制台：**系统管理 → 用户管理 → 创建用户**。

创建后，将用户加入指定项目并分配合适角色。

## CI/CD 账号

流水线推送镜像建议使用独立账号（如 `jenkins`、`gitlab-ci`、`tekton`），不要使用 `admin`。权限只授予需要推送的项目。

## Kubernetes 拉取私有镜像

如果 Harbor 项目是私有的，Kubernetes 需配置 imagePullSecrets。

创建 Secret：

```bash
kubectl create secret docker-registry harbor-secret \
  --docker-server=harbor.example.com \
  --docker-username=developer \
  --docker-password=YourPassword \
  --docker-email=admin@example.com \
  -n default
```

注意事项：

- Secret 只在所在 namespace 生效。业务部署在 `prod` namespace 时，需要在 `prod` namespace 创建同名 Secret。
- `--docker-password` 建议使用 Harbor 机器人账号或专用 CI/CD 账号的 Token，不建议使用个人账号或 `admin` 密码。
- 如果 Harbor 使用自签 HTTPS，Kubernetes 节点的 containerd 仍然要信任 Harbor CA；`imagePullSecrets` 只解决认证，不解决证书信任。

在 Pod 中引用：

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  imagePullSecrets:
    - name: harbor-secret
  containers:
    - name: nginx
      image: harbor.example.com/base/nginx:alpine
```

在 Deployment 中引用：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
spec:
  template:
    spec:
      imagePullSecrets:
        - name: harbor-secret
      containers:
        - name: api-server
          image: harbor.example.com/business/api-server:v1.0.0
```

如果使用 ServiceAccount，可以把 imagePullSecrets 挂载到 ServiceAccount 上，避免每个 Pod 都要声明：

```bash
kubectl patch serviceaccount default \
  -n default \
  -p '{"imagePullSecrets":[{"name":"harbor-secret"}]}'
```

验证：

```bash
kubectl get serviceaccount default -n default -o yaml
kubectl run pull-test \
  --image=harbor.example.com/base/nginx:alpine \
  --restart=Never \
  -n default
kubectl describe pod pull-test -n default
```
