# 03-6 Harbor 仓库多用户权限管理

Harbor 通过项目、用户、用户组和角色控制镜像访问权限。企业环境中不建议所有人共用 `admin` 账号，应按团队和项目拆分权限。

## 权限管理对象

| 对象 | 作用 |
| --- | --- |
| 用户 | Harbor 登录账号 |
| 项目 | 镜像隔离单元，例如 `base`、`devops`、`business` |
| 成员 | 用户或用户组加入项目后的身份 |
| 角色 | 决定成员在项目中的操作权限 |

## 常见角色

| 角色 | 适用场景 |
| --- | --- |
| 项目管理员 | 管理项目成员、镜像、复制、扫描等项目级配置 |
| 维护人员 | 维护项目镜像和仓库配置，但不负责全局管理 |
| 开发人员 | 推送和拉取镜像，适合 CI/CD 或开发成员 |
| 访客 | 只读访问，适合测试、运维或只需要拉取镜像的用户 |
| 受限访客 | 更受限的只读访问场景 |

实际权限以 Harbor 当前版本页面展示为准。

## 推荐项目划分

按业务划分：

```text
mall
payment
user-center
```

按环境划分：

```text
dev
test
prod
```

按镜像类型划分：

```text
base
middleware
business
```

小团队可以按业务划分，大团队建议结合组织、业务线和环境设计。

## 创建普通用户

在 Harbor Web 控制台中进入：

```text
系统管理 -> 用户管理 -> 创建用户
```

创建完成后，把用户加入指定项目，并分配合适角色。

## CI/CD 账号建议

流水线推送镜像时建议使用独立账号，例如：

```text
jenkins
gitlab-ci
tekton
```

账号权限只授予需要推送的项目，不要直接使用 `admin`。

## Kubernetes 拉取私有镜像

如果 Harbor 项目是私有项目，Kubernetes 需要配置镜像拉取密钥：

```bash
kubectl create secret docker-registry harbor-secret \
  --docker-server=YOUR_HARBOR_ADDRESS \
  --docker-username=YOUR_USERNAME \
  --docker-password=YOUR_PASSWORD \
  --docker-email=admin@example.com \
  -n default
```

Pod 中引用：

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
      image: YOUR_HARBOR_ADDRESS/library/nginx:alpine
```
