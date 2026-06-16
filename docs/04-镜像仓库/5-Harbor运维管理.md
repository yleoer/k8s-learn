# Harbor 运维管理

镜像仓库使用一段时间后会积累大量历史镜像。只删除标签不一定释放磁盘空间，需结合保留策略和垃圾回收处理。多机房场景还需配置镜像复制同步。

## 镜像清理

### 手动删除

Web 控制台：**项目 → 镜像仓库 → 选择镜像 → 删除指定 tag**。

删除前确认该镜像没有被 Kubernetes、发布系统或回滚流程继续使用。

### 标签保留策略

按项目配置自动清理规则，例如：

```text
保留最近 10 个镜像标签
保留所有 v 开头的正式版本
清理 30 天前的临时构建镜像（dev-*、test-*）
```

配置路径：**项目 → 策略 → 标签保留策略 → 添加规则**。

## 垃圾回收（GC）

删除标签后，底层 blob 数据不会立即释放，需执行垃圾回收。

Web 控制台：**系统管理 → 垃圾回收 → 立即执行**。

也可配置定时 GC：

```bash
# 在 harbor.yml 中配置
gc:
  schedule: "0 0 2 * * *"    # 每天凌晨 2 点
```

### GC 注意事项

- GC 执行期间 Harbor 进入只读模式，镜像推送和删除会暂停。
- 建议安排在业务低峰期执行。
- 数据量大时 GC 可能耗时较长。

## 磁盘检查

```bash
du -sh /data/harbor
df -h
```

Harbor 数据目录建议单独挂载磁盘，便于扩容和监控。重点关注 `/data/harbor/registry` 目录的占用。

## 镜像复制

镜像复制用于在不同 Harbor 实例之间同步镜像，典型场景：

| 场景 | 说明 |
| --- | --- |
| 测试 → 生产 | 验证通过后同步指定版本到生产 Harbor |
| 总部 → 分支机房 | 减少跨地域拉取镜像的网络延迟 |
| 外网 → 内网 | 将 Docker Hub 镜像同步到内网 Harbor |
| 多集群共享 | 每个集群从就近 Harbor 拉取 |

### 配置复制

1. 创建目标仓库（**系统管理 → 仓库管理 → 新建目标**）。
2. 配置目标地址、用户名、密码。
3. 创建复制规则（**项目 → 复制 → 新建规则**）。
4. 设置复制方向（推送 / 拉取）、过滤条件（仓库名、标签）。
5. 手动执行或配置事件触发（推送触发、定时触发）。

### 复制规则示例

```text
方向：推送
源项目：business
仓库：api-server
标签：v*
```

只同步正式版本，避免将临时构建镜像复制到生产仓库。

### 验证复制

在目标仓库拉取镜像：

```bash
docker login harbor-prod.example.com
docker pull harbor-prod.example.com/business/api-server:v1.0.0
```

## 备份建议

Harbor 备份不是简单复制目录。生产环境建议在维护窗口内执行，先暂停推送和删除操作，保证数据库和 registry 数据一致。

建议备份以下内容：

| 内容 | 说明 |
| --- | --- |
| `harbor.yml` | Harbor 核心配置、域名、证书路径、数据目录 |
| `/data/harbor` | registry blob、job 日志、数据库数据等 |
| PostgreSQL 数据库 | 项目、用户、权限、tag、artifact 元数据 |
| 证书和密钥 | HTTPS 证书、私钥、内部 secret |
| Harbor 版本 | 恢复时尽量使用相同 Harbor 版本 |

### 维护窗口备份流程

进入 Harbor 安装目录，先停止写入流量。小规模实验环境可以直接停止 Harbor：

```bash
cd /opt/harbor
docker compose stop
```

备份配置、证书和数据目录：

```bash
backup_date=$(date +%Y%m%d)
mkdir -p /backup/harbor-${backup_date}

cp harbor.yml /backup/harbor-${backup_date}/harbor.yml
cp -a /etc/harbor/certs /backup/harbor-${backup_date}/certs 2>/dev/null || true
tar czf /backup/harbor-${backup_date}/data-harbor.tar.gz /data/harbor
```

重新启动 Harbor：

```bash
docker compose up -d
docker compose ps
```

如果不方便停机，可以至少进入只读或暂停 CI/CD 推送任务后，再备份数据库和 registry 数据。不要在大量推送同时进行时直接复制数据目录。

### 数据库导出

Harbor 数据库（PostgreSQL）可通过 `docker exec` 执行 `pg_dump`。不同版本容器名可能略有差异，先确认：

```bash
docker compose ps
```

常见导出方式：

```bash
docker exec harbor-db pg_dump -U postgres registry > /backup/harbor-${backup_date}/harbor-db.sql
```

如果数据库用户名、库名与环境不一致，以 `harbor.yml` 和容器环境变量为准。

### 恢复校验

恢复后至少检查：

```bash
docker compose ps
curl -I https://harbor.example.com
docker login harbor.example.com
docker pull harbor.example.com/base/nginx:alpine
```

还应在 Web 控制台确认项目、用户、机器人账号、复制规则、保留策略和扫描配置是否存在。

## 本章回顾

完成本章后，你应该具备以下能力：

- 理解镜像仓库的作用和镜像地址命名规范。
- 独立完成 Harbor 离线安装和基本配置。
- 向 Harbor 推送和拉取镜像。
- 配置 Docker 和 containerd 对接 HTTP / 自签证书的 Harbor。
- 理解 Harbor 的项目、用户、角色体系，能合理拆分权限。
- 为 Kubernetes 配置 imagePullSecrets 拉取私有仓库镜像。
- 配置镜像保留策略、执行垃圾回收、管理磁盘空间。
- 配置镜像复制实现多仓库同步。

下一步进入第 07 章，深入学习 Containerd 容器运行时。
