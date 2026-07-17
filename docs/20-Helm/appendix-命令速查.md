# Helm 命令速查

本章整理 Chart、Release、OCI 仓库与发布检查命令。Helm 负责渲染并提交资源，不替代 Kubernetes 授权、准入、镜像供应链或运行中工作负载验证。

## 关键对象与边界

| 对象 | 作用 | 不负责 |
| --- | --- | --- |
| Chart | 可版本化的模板与默认值包 | 记录某次实际安装状态 |
| Release | Chart 在集群中的一次安装 | 保证业务兼容性 |
| `values.yaml` | 保存非敏感默认参数 | 保存生产凭据 |
| OCI registry | 分发 Chart artifact | 管理 Kubernetes RBAC |

## 命令速查

### Chart 创建与渲染

```bash
helm create web
helm lint ./web
helm template web ./web --namespace team-a --values ./web/values.yaml
helm show chart oci://<registry.example.com>/<namespace>/web --version <chart-version>
```

### OCI 与依赖

```bash
helm registry login <registry.example.com>
helm push ./web-<chart-version>.tgz oci://<registry.example.com>/<namespace>
helm pull oci://<registry.example.com>/<namespace>/web --version <chart-version>
helm dependency build ./platform-app
```

### 发布与排障

```bash
helm upgrade --install web ./web --namespace team-a --create-namespace
helm list -n team-a
helm status web -n team-a
helm get manifest web -n team-a
helm rollback web <revision> -n team-a
```

## 配置速查

| 配置 | 检查重点 |
| --- | --- |
| `Chart.yaml.version` | Chart 版本，模板与依赖变化时递增 |
| `appVersion` | 展示元数据，不会自动设置镜像 tag |
| `Chart.lock` | 固定已解析依赖版本 |
| 环境 values 文件 | 仅保存受审查的环境差异，不保存明文密钥 |

## 排查索引

| 现象 | 优先检查 | 正文 |
| --- | --- | --- |
| 模板渲染失败 | `helm lint`、`helm template` 和 values 类型 | [模板与 Values](./3-模板与Values.md) |
| Release 失败 | Helm 状态、事件、准入和工作负载状态 | [Helm 安全与排障](./8-Helm安全与排障.md) |
| 升级后回退 | Release 历史、不可变字段和渲染差异 | [发布更新与回滚](./6-发布更新与回滚.md) |

## 关联页面

- [Chart 结构与创建](./2-Chart结构与创建.md)
- [OCI 仓库与依赖](./5-OCI仓库与依赖.md)
- [微服务 Chart 边界](./7-微服务Chart边界.md)

## 参考

- [Helm 文档](https://helm.sh/docs/)
