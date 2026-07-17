# 微服务 Chart 边界

一个 Chart 的边界应与发布和回滚边界一致。独立扩缩、独立故障恢复或独立授权的服务通常使用独立 Chart；需要原子协调发布的一组资源可以组织为一个应用 Chart 或由上层编排工具管理。

## 参数层次

| 文件或来源 | 适合保存 | 不应保存 |
| --- | --- | --- |
| `values.yaml` | 通用副本数、镜像仓库、资源默认值 | 生产密码、私钥、集群地址 |
| 环境 values 文件 | 环境差异、域名、容量 | 未加密的 Secret 内容 |
| 外部 Secret 引用 | Secret 名称、键名、挂载方式 | 明文凭据 |
| CI/CD 注入 | 短期令牌、审计元数据 | 长期管理员 kubeconfig |

Chart 只生成声明式资源，不负责自动判断业务兼容性、执行不可逆数据迁移或跨集群事务。数据库变更需要单独的备份、演练和回滚策略。

## 验证门槛

每次 Chart 修改至少检查 `helm lint`、`helm template`、渲染 YAML、目标命名空间的准入结果和工作负载就绪状态。复杂 Chart 还应加入单元测试或集成测试，而不是只验证 Helm 命令退出码。

## 参数文件验证

复用[Chart 结构与创建](./2-Chart结构与创建.md#参数文件)中通过 `helm create web` 创建的完整 `web` Chart。下面的环境覆盖文件只表达该服务的容量和镜像差异，不保存凭据：

```yaml [web/values-team-a.yaml]
replicaCount: 2
image:
  repository: nginx
  tag: 1.31-alpine
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi
```

```bash
helm lint ./web
helm template web ./web --namespace team-a \
  --values ./web/values.yaml \
  --values ./web/values-team-a.yaml
```

渲染结果应确认镜像、resources、名称和 labels 均属于同一个 Release。通过本地渲染后，仍需在目标集群检查准入、Secret 引用和 Pod 就绪状态。

## 参考

- [Chart 最佳实践](https://helm.sh/docs/chart_best_practices/)
