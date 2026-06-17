# Harbor 权限管理

Harbor 通过项目、用户和角色控制镜像访问权限。企业环境不应让开发、测试、运维和流水线共用 `admin` 账号，否则既不符合最小权限原则，也难以追溯具体操作来源。

## 权限模型

| 对象 | 说明 |
| --- | --- |
| 用户 | Harbor 登录账号，可以是本地账号，也可以来自 LDAP 或 OIDC |
| 项目 | 镜像和制品的隔离单元，每个项目可设置为公开或私有 |
| 角色 | 决定用户在项目内可执行的操作范围 |
| Robot 账号 | 面向自动化系统的专用账号，常用于 CI/CD 推送和集群拉取 |

同一个用户可以在不同项目中拥有不同角色。例如，某开发者在 `dev` 项目中具备开发人员权限，在 `prod` 项目中仅具备访客权限。

## 内置角色

| 角色 | 权限范围 | 典型分配对象 |
| --- | --- | --- |
| 项目管理员 | 管理成员、镜像、复制、扫描、策略等项目配置 | 团队负责人、平台管理员 |
| 维护人员 | 管理镜像和项目配置，不能管理项目成员 | 高级开发者、发布负责人 |
| 开发人员 | 推送和拉取镜像 | 日常开发者、构建流水线 |
| 访客 | 只读拉取镜像 | 测试、运维、跨团队使用方 |
| 受限访客 | 更严格的只读访问 | 外部合作方、临时审计账号 |

权限分配应优先从只读权限开始，根据实际职责逐步增加写入或管理权限。

## 项目划分建议

项目划分会直接影响权限配置、镜像清理和复制策略。常见划分方式如下。

按业务划分，适合团队边界清晰的场景：

```text
mall
payment
user-center
```

按环境划分，适合发布流程严格区分开发、测试和生产的场景：

```text
dev
test
prod
```

按镜像类型划分，适合平台团队集中维护基础镜像和中间件镜像：

```text
base
middleware
business
```

实际落地时可以组合使用，例如 `dev-mall`、`prod-payment`。项目数量不宜过少，否则权限边界模糊；也不宜过细，否则用户和策略维护成本过高。

## 创建用户

Harbor Web 控制台路径：**系统管理 → 用户管理 → 创建用户**。

用户创建后，需要进入对应项目的成员管理页面添加用户并分配角色。例如：

- `zhangsan` 加入 `mall` 项目，角色为开发人员，可推送和拉取业务镜像
- `lisi` 加入 `prod` 项目，角色为访客，只能拉取生产镜像

`admin` 账号仅用于安装、全局配置变更和紧急故障处理。日常操作应使用可审计的个人账号或自动化专用账号。

## Robot 账号

CI/CD 流水线、Kubernetes 拉取任务和跨系统集成应优先使用 Robot 账号，而不是个人账号或 `admin` 账号。Robot 账号可以绑定到项目，并设置更明确的权限范围和有效期。

项目级 Robot 账号示例：

```text
名称：robot$mall-ci
项目：mall
权限：push、pull
用途：Jenkins 或 GitLab CI 构建后推送镜像
```

使用 Robot 账号登录时，用户名和 Token 均以 Harbor 控制台生成结果为准。Token 应作为流水线密文变量保存，不应写入仓库。

## Kubernetes 拉取私有镜像

如果 Harbor 项目为私有项目，Kubernetes 需要通过 `imagePullSecret` 提供拉取凭据。Secret 属于命名空间资源，每个需要拉取私有镜像的命名空间都要配置。

### 创建 imagePullSecret

```bash
kubectl create secret docker-registry harbor-secret \
  --docker-server=harbor.example.com \
  --docker-username=developer \
  --docker-password=YourPassword \
  -n default
```

`--docker-username` 可以使用普通用户，也可以使用 Robot 账号；生产环境更推荐使用权限受限的 Robot 账号。

### 在 Pod 中引用

```yaml
spec:
  imagePullSecrets:
    - name: harbor-secret
  containers:
    - name: nginx
      image: harbor.example.com/base/nginx:alpine
```

### 在 Deployment 中引用

```yaml
spec:
  template:
    spec:
      imagePullSecrets:
        - name: harbor-secret
      containers:
        - name: api-server
          image: harbor.example.com/business/api-server:v1.0.0
```

### 绑定到 ServiceAccount

将 `imagePullSecret` 绑定到命名空间默认 ServiceAccount 后，该命名空间中新创建的 Pod 会自动携带拉取凭据，避免在每个工作负载中重复声明：

```bash
kubectl patch serviceaccount default \
  -n default \
  -p '{"imagePullSecrets": [{"name": "harbor-secret"}]}'
```

已有 Pod 不会因为 ServiceAccount 更新而自动重建，需要重新创建或滚动更新工作负载后才会使用新的拉取凭据。

> `imagePullSecret` 中存储的是经过 base64 编码的认证信息，并不是加密密文。相关 YAML 不应提交到公开仓库，生产环境可结合 External Secrets、Vault 或 SealedSecrets 管理凭据。
