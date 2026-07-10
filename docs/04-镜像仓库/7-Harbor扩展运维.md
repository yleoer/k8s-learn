# Harbor 扩展运维

前面的 Harbor 运维记录关注标签保留、垃圾回收、复制和备份。仓库进入长期运行后，还需要补充 Proxy Cache、项目配额、审计日志和升级回滚，这些能力影响公网依赖、容量边界、操作追踪和版本演进。

## Proxy Cache

Proxy Cache 用于让 Harbor 代理并缓存上游 Registry 的镜像。它适合内网节点需要访问 Docker Hub、Quay、GHCR 或其他外部仓库，但直接出网受限、带宽成本较高或容易触发上游限流的场景。

Proxy Cache 通过特殊项目承载。该项目连接到一个 Registry endpoint，拉取请求进入 Harbor 后，如果本地没有缓存，Harbor 会从上游拉取并返回给客户端，同时缓存结果；后续请求会根据上游清单状态决定继续使用缓存或刷新缓存。

Proxy Cache 项目和普通项目的关键差异如下：

| 对比项    | Proxy Cache 项目                | 普通项目             |
|--------|-------------------------------|------------------|
| 镜像来源   | 上游 Registry                   | 用户或流水线推送         |
| 推送能力   | 不能向 Proxy Cache 项目推送镜像        | 可以按权限推送          |
| 使用方式   | 镜像地址增加 Harbor 和代理项目名前缀        | 直接引用 Harbor 项目路径 |
| 默认保留策略 | 新建 Proxy Cache 项目默认创建 7 天保留策略 | 按项目单独配置          |

拉取示例：

```bash
docker pull harbor.example.com/dockerhub/library/nginx:1.31-alpine
```

Pod 中引用时也使用代理项目路径：

```yaml{8}
apiVersion: v1
kind: Pod
metadata:
  name: proxy-cache-nginx
spec:
  containers:
    - name: nginx
      image: harbor.example.com/dockerhub/library/nginx:1.31-alpine
```

上游账号的权限会影响 Proxy Cache 可拉取的镜像范围。配置私有上游仓库时，应使用权限受限的账号或 Token，避免让 Harbor 项目成员间接访问超出预期的上游镜像。

## 项目配额

项目配额用于限制 Harbor 项目可消耗的存储容量。系统管理员可以设置全局默认配额，也可以为单个项目设置独立配额；单个项目配额会覆盖全局默认配额。

Harbor 默认项目存储配额为无限制。全局默认配额只作用于设置之后新建的项目，不会自动改写已经存在的项目。

常见配置记录：

```text
全局默认配额：50 GiB
base 项目：20 GiB
business 项目：200 GiB
proxy-cache 项目：100 GiB
```

配额限制的是项目存储消耗，不等同于磁盘监控。Registry 数据目录、数据库、任务日志、Trivy 缓存和系统日志仍需要独立监控。项目触达配额后会影响继续推送或缓存新制品，但不会替代垃圾回收和底层磁盘扩容。

## 审计日志

Harbor 审计日志记录拉取、推送、删除制品、创建和更新用户、登录登出、配置变更、项目和 Robot 账号变更等操作。审计日志用于追踪“谁在什么时候对什么资源做了什么操作”，不等同于容器运行日志或 Registry 访问日志。

Harbor v2.13.0 之后的审计日志在界面中有新的 `Audit Logs` 视图，旧数据仍可通过 legacy 视图查看。查询时可以按操作类型、用户名、操作、资源和资源类型过滤。

运维上需要关注两类设置：

| 设置        | 作用             | 风险                  |
|-----------|----------------|---------------------|
| 审计日志保留窗口  | 定期清理数据库中的审计日志  | 保留时间过短会影响追溯         |
| Syslog 转发 | 将审计日志转发到外部日志系统 | 外部端点不可用时需确认是否仍写入数据库 |

如果启用 `Skip Audit Log Database`，Harbor 会直接转发审计日志而不在数据库中保留记录。该选项应在外部日志平台可靠接收、检索和备份后再启用。

## 日志轮转

Harbor 的日志轮转用于清理审计日志记录。可配置按小时、每天、每周或自定义 cron 执行，也可以通过 `DRY RUN` 预演清理结果。

轮转策略需要和审计要求对齐。例如，生产环境可以保留 90 天数据库审计日志，同时转发到集中日志系统保存更长周期。清理任务的历史记录应定期查看，避免任务失败导致数据库持续膨胀。

## 升级与回滚

Harbor 升级可能修改 `harbor.yml` 和数据库 schema，升级前必须备份配置、数据库和 Registry 数据。官方 Harbor 2.15 升级指南覆盖从 v2.12.0 及之后版本迁移到 v2.15.0；更早版本应先按对应历史版本的迁移指南分段升级。

升级前记录：

```bash
cp harbor.yml /backup/harbor.yml.$(date +%Y%m%d)
cp -r /data/harbor/database /backup/database.$(date +%Y%m%d)
tar czf /backup/harbor-registry-$(date +%Y%m%d).tar.gz /data/harbor/registry
```

升级流程中，官方文档使用 prepare 镜像迁移配置：

```bash
docker run -it --rm \
  -v /:/hostfs \
  goharbor/prepare:<new-version> \
  migrate -i /path/to/harbor.yml
```

数据库 schema 迁移在 Harbor core 启动时执行。升级失败时，应先查看 `harbor-core` 日志，再决定恢复还是继续修复。

回滚不是降级。Harbor 官方文档明确说明，回滚依赖升级前保留的旧版本 Harbor 文件和数据库备份；Harbor 不支持降级，数据库 schema 不会自动回退。没有同一时间点的配置、数据库和 Registry 数据备份时，不应假设可以安全回退。

回滚前置条件：

- 升级前完整保留旧版本 `harbor` 目录。
- 升级前备份数据库目录或数据库快照。
- Registry 数据与数据库元数据处于一致时间点。
- 证书、内部 TLS、外部数据库和对象存储配置可恢复。

回滚记录应包含旧版本号、新版本号、升级开始时间、备份位置、迁移命令、失败现象、恢复步骤和验证结果。

## 参考

- [Harbor Configure Proxy Cache](https://goharbor.io/docs/2.15.0/administration/configure-proxy-cache/)
- [Harbor Configure Project Quotas](https://goharbor.io/docs/2.15.0/administration/configure-project-quotas/)
- [Harbor Audit Log](https://goharbor.io/docs/2.15.0/administration/audit-log/)
- [Harbor Log Rotation](https://goharbor.io/docs/2.15.0/administration/log-rotation/)
- [Harbor Upgrade and Migrate Data](https://goharbor.io/docs/2.15.0/administration/upgrade/)
- [Harbor Roll Back from an Upgrade](https://goharbor.io/docs/2.15.0/administration/upgrade/roll-back-upgrade/)
