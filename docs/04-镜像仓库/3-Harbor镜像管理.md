# Harbor 镜像管理

Harbor 安装完成后，需要验证从客户端推送镜像、从其他节点拉取镜像的完整链路。若 Harbor 使用 HTTP 或未被系统信任的证书，还需要分别配置 Docker 与 containerd 的仓库访问规则。

## 登录测试

```bash
docker login harbor.example.com
```

输入具备项目权限的用户名和密码。登录成功后，Docker 会将认证信息写入 `~/.docker/config.json`，后续执行 `docker push` 和 `docker pull` 时会自动携带凭据。

## 创建项目

在 Harbor Web 控制台进入 **项目 → 新建项目**，创建一个名为 `base` 的项目。

| 类型   | 说明                  | 适用场景             |
|------|---------------------|------------------|
| 公开项目 | 未登录用户可以拉取镜像，但推送仍需权限 | 基础镜像、公共组件、开源镜像缓存 |
| 私有项目 | 用户必须登录并具备项目权限才能拉取   | 业务镜像、内部中间件、生产镜像  |

基础镜像可放入公开的 `base` 项目，业务镜像通常放入私有项目，并通过用户、Robot 账号或 Kubernetes Secret 控制访问。

Docker Hub 会对镜像拉取频率做限制，具体额度可能随账号类型和官方策略调整。内网基础镜像缓存和私有仓库可以减少外部 Registry 访问波动。

## 推送镜像到 Harbor

```bash
# 拉取一个测试镜像
docker pull nginx:1.31-alpine

# 打标签，指向 Harbor 中的 base 项目
docker tag nginx:1.31-alpine harbor.example.com/base/nginx:1.31-alpine

# 推送镜像
docker push harbor.example.com/base/nginx:1.31-alpine
```

推送完成后，可在 Harbor 控制台进入 `base` 项目查看 `nginx` 仓库和 `1.31-alpine` 标签。若推送失败，应检查项目是否存在、账号是否具备开发人员及以上权限，以及客户端是否信任 Harbor 地址。

## 拉取验证

在另一台节点上验证拉取链路：

```bash
docker login harbor.example.com
docker pull harbor.example.com/base/nginx:1.31-alpine
```

公开项目可以省略 `docker login` 执行拉取；私有项目必须登录，或由运行时通过预置凭据完成认证。

## 配置 Docker 访问

生产环境推荐使用受信任的 HTTPS 证书。若 Harbor 使用 HTTP，可以在 `/etc/docker/daemon.json` 中配置 `insecure-registries`：

```json{2} [daemon.json]
{
  "insecure-registries": ["harbor.example.com"]
}
```

带非标准端口时必须写出端口：

```json{2} [daemon.json]
{
  "insecure-registries": ["harbor.example.com:8080"]
}
```

修改后重启 Docker：

```bash
sudo systemctl restart docker
docker login harbor.example.com
```

若 Harbor 使用内部 CA 或自签 CA，更推荐把 CA 证书安装到 Docker 信任目录，而不是关闭校验。该目录按连接读取，无需重启 Docker：

```bash
sudo mkdir -p /etc/docker/certs.d/harbor.example.com
sudo cp ca.crt /etc/docker/certs.d/harbor.example.com/ca.crt
```

## 配置 containerd 访问

Kubernetes 节点使用 containerd 时，Docker 的配置不会自动生效，需要单独配置 `/etc/containerd/certs.d/` 下的 `hosts.toml`。

> [!IMPORTANT]
> `hosts.toml` 只有在 containerd 主配置启用 `config_path` 后才会被读取，第 01 章安装 containerd 时已完成该配置。`config_path` 的启用方式和更完整的访问策略在第 05 章《镜像仓库配置》中单独整理。

### HTTP 仓库

```bash
sudo mkdir -p /etc/containerd/certs.d/harbor.example.com

sudo tee /etc/containerd/certs.d/harbor.example.com/hosts.toml >/dev/null <<'EOF'
server = "http://harbor.example.com"

[host."http://harbor.example.com"]
  capabilities = ["pull", "resolve", "push"]
EOF

sudo systemctl restart containerd
```

### 自签或内部 CA 证书

更稳妥的方式是分发 CA 证书并显式配置 `ca`：

```bash
sudo mkdir -p /etc/containerd/certs.d/harbor.example.com
sudo cp ca.crt /etc/containerd/certs.d/harbor.example.com/ca.crt

sudo tee /etc/containerd/certs.d/harbor.example.com/hosts.toml >/dev/null <<'EOF'
server = "https://harbor.example.com"

[host."https://harbor.example.com"]
  capabilities = ["pull", "resolve", "push"]
  ca = "/etc/containerd/certs.d/harbor.example.com/ca.crt"
EOF

sudo systemctl restart containerd
```

临时测试也可以使用 `skip_verify = true` 跳过证书校验，但不建议在生产环境长期使用。

验证 containerd 能否拉取镜像：

```bash
sudo crictl pull harbor.example.com/base/nginx:1.31-alpine
sudo crictl images | grep harbor
```

## HTTPS 权威证书场景

如果 Harbor 使用权威 CA 签发的 HTTPS 证书，且节点系统信任该 CA，Docker 和 containerd 通常不需要额外配置。客户端会通过系统证书池完成校验，这也是生产环境优先采用受信任 HTTPS 的主要原因。

## 镜像标签策略

标签不仅区分版本，也影响回滚、审计和排障效率。常见策略如下：

| 策略         | 示例                  | 适用场景       |
|------------|---------------------|------------|
| 语义版本       | `v1.0.0`、`v2.3.1`   | 正式发布       |
| Git commit | `abc1234`、`9f3c2a1` | 开发环境快速验证   |
| 构建序号       | `20260617-001`      | CI/CD 自动构建 |
| 环境加版本      | `prod-v1.0.0`       | 多环境版本区分    |

生产发布应避免仅使用 `latest` 标签。`latest` 只是普通标签，不一定代表最新构建，也无法稳定定位到某一次发布内容。

## 不可变标签

标签默认可以被覆盖：向同一个 `repository:tag` 再次推送会直接替换其内容，回滚和审计随之失去依据。Harbor 的不可变标签规则（Tag Immutability Rules）在项目级把指定标签固定下来。

配置路径：**项目 → 策略 → 不可变标签 → 添加规则**。规则由仓库匹配和标签匹配两部分组成，均支持逗号分隔列表和 `**` 通配符，并可选择 matching 或 excluding 模式；多条规则之间是或的关系，每个项目最多 15 条规则。

示例规则：

```text
仓库：匹配 **        标签：匹配 v*        # 所有仓库的正式版本标签不可变
仓库：匹配 **        标签：排除 dev-*     # 除 dev- 前缀外全部固定
```

标签命中规则后：

- 不能通过再次推送覆盖，客户端会收到 `412 Precondition Failed`，错误信息形如 `configured as immutable`。
- 不能删除该标签，持有该标签的制品也不能删除；同一制品上其他未命中规则的标签仍可以删除。
- 重新打标签和从其他 Registry 复制进来的覆盖同样被拒绝。
- 标签保留策略在执行时会跳过不可变制品，不会将其清理。

> [!TIP]
> 不可变标签与标签保留策略配合使用：`v*` 等正式发布标签设为不可变，保证可回滚可审计；`dev-*`、`test-*` 等临时标签交给保留策略定期清理。CI 流水线重复推送同名正式标签会因 412 失败，这是预期行为，版本号应递增而不是复用。

## 参考

- [Pulling and Pushing Images](https://goharbor.io/docs/2.15.0/working-with-projects/working-with-images/pulling-pushing-images/)
- [Create Tag Immutability Rules](https://goharbor.io/docs/2.15.0/working-with-projects/working-with-images/create-tag-immutability-rules/)
- [Configure Docker daemon.json](https://docs.docker.com/reference/cli/dockerd/#daemon-configuration-file)
- [containerd Registry Configuration](https://github.com/containerd/containerd/blob/main/docs/hosts.md)
