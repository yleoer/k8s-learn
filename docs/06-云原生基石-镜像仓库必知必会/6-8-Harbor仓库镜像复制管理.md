# 03-8 Harbor 仓库镜像复制管理

镜像复制用于在不同 Harbor 实例或不同镜像仓库之间同步镜像。企业中常见场景是多机房、多集群、测试到生产、内外网仓库同步。

## 常见复制场景

| 场景 | 说明 |
| --- | --- |
| 测试仓库同步到生产仓库 | 测试验证通过后，把指定版本复制到生产 Harbor |
| 总部同步到分支机房 | 减少跨地域拉取镜像的网络依赖 |
| 公共镜像同步到内网 | 把 Docker Hub 或云厂商镜像同步到内网仓库 |
| 多 Kubernetes 集群共享镜像 | 每个集群从就近 Harbor 拉取镜像 |

## 复制配置流程

在 Harbor Web 控制台中一般按下面流程配置：

1. 创建目标仓库 Endpoint。
2. 配置访问地址和认证信息。
3. 创建复制规则。
4. 设置复制方向、项目、仓库和标签过滤条件。
5. 手动执行或配置事件触发复制。

## Endpoint 配置

Endpoint 表示远端镜像仓库，例如另一个 Harbor：

```text
https://harbor-prod.example.com
```

需要配置：

- 目标仓库地址。
- 用户名和密码。
- 是否校验证书。
- 连接测试。

如果目标仓库使用自签证书，需要保证 Harbor 能信任该证书，或者在测试环境中按需关闭证书校验。

## 复制规则

复制规则可以限制同步范围：

```text
项目：business
仓库：api-server
标签：v*
```

这样可以只复制正式版本，避免把临时构建镜像同步到生产仓库。

## 推荐实践

- 测试环境可以推送 `dev-*`、`test-*` 标签。
- 生产环境只接收明确版本标签，例如 `v1.0.0`。
- 复制规则尽量精确，避免全量复制导致磁盘快速增长。
- 多机房场景中，建议每个机房都有本地 Harbor。
- 复制失败时优先检查网络、账号权限、证书和目标项目是否存在。

## 复制后的验证

在目标仓库登录并拉取镜像：

```bash
docker login harbor-prod.example.com
docker pull harbor-prod.example.com/business/api-server:v1.0.0
```

Kubernetes 发布前确认 Deployment 中使用的是目标仓库地址：

```yaml
image: harbor-prod.example.com/business/api-server:v1.0.0
```
