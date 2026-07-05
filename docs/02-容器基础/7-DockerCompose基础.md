# Docker Compose 基础

服务的容器数量一多，`docker run` 的参数就会越来越长，网络、卷和启动顺序也要靠人工维护。Docker Compose 用一个 `compose.yaml` 文件声明整组服务，通过 `docker compose` 命令统一创建、更新和销毁。第 04 章的 Harbor 就是用 Compose 部署的多容器应用。

## Compose 形态

当前的 Compose 是 Docker CLI 的插件，命令为 `docker compose`，按 Docker 官方指引安装 Docker Engine 时会随 `docker-compose-plugin` 包一并安装。早期 Python 实现的独立命令 `docker-compose`（V1）已停止维护，遗留脚本应迁移到 `docker compose`。Compose v2 之后的当前大版本是 v5（2025 年 12 月发布），功能与 v2 保持一致，编号跳过 v3、v4 是为了避免与旧配置文件格式版本混淆。

确认安装与版本：

```bash
docker compose version
```

## 配置文件

Compose 默认按顺序查找 `compose.yaml`（推荐）、`compose.yml`，并兼容旧的 `docker-compose.yaml`、`docker-compose.yml`；同时存在时优先使用 `compose.yaml`。

配置文件遵循 Compose Specification，旧的 file format 2.x、3.x 已合并进该规范，顶层 `version` 字段随之废弃——写了也会被忽略并产生警告，Compose 始终按最新规范校验文件。

顶层元素：

| 元素         | 作用                |
|------------|-------------------|
| `services` | 服务定义，每个服务对应一组同构容器 |
| `networks` | 自定义网络             |
| `volumes`  | 命名卷               |
| `configs`  | 配置对象              |
| `secrets`  | 敏感配置对象            |

## 最小示例

沿用 [持久化与服务部署](./5-持久化与服务部署.md) 中的静态页面场景，增加一个用于验证服务发现的客户端容器：

```bash
mkdir -p ./html
echo 'hello compose' > ./html/index.html
```

```yaml [compose.yaml]
services:
  web:
    image: nginx:1.27-alpine
    ports:
      - "8080:80"
    volumes:
      - ./html:/usr/share/nginx/html:ro
    restart: unless-stopped
  client:
    image: busybox:1.36.1
    command: sleep infinity
    depends_on:
      - web
```

启动并验证：

```bash
docker compose up -d
docker compose ps
curl http://127.0.0.1:8080
docker compose exec client wget -qO- http://web
```

最后一条命令在 `client` 容器内通过服务名 `web` 访问 nginx，预期返回 `hello compose`。清理环境：

```bash
docker compose down
```

## 默认网络与服务发现

`docker compose up` 会自动创建名为 `<项目名>_default` 的 bridge 网络，项目名默认取配置文件所在目录名，可用 `-p` 或 `COMPOSE_PROJECT_NAME` 覆盖。所有服务默认加入该网络，服务名注册为网络内 DNS 名称。

服务间互访应始终使用服务名：容器 IP 在重建后会变化，服务名解析始终指向当前容器。这与上一篇自定义 bridge 网络的行为一致，Compose 只是把网络创建和名称注册自动化了。

## 启动顺序

`depends_on` 控制服务启动顺序。简单列表形式只保证“容器已启动”，不保证“应用已就绪”；需要等待就绪时使用 `condition` 长格式：

```yaml [compose.yaml]
services:
  app:
    image: busybox:1.36.1
    command: sh -c "echo db is ready && sleep infinity"
    depends_on:
      db:
        condition: service_healthy
  db:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: example  # 学习环境示例；生产环境应使用 secrets 注入
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "127.0.0.1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
```

`condition` 支持三种取值：

| 取值                               | 含义                                |
|----------------------------------|-----------------------------------|
| `service_started`                | 依赖容器已启动，等价于短格式                    |
| `service_healthy`                | 依赖服务健康检查通过，需要对应服务定义 `healthcheck` |
| `service_completed_successfully` | 依赖服务成功运行结束，适合初始化类一次性任务            |

`docker compose up app` 时，Compose 会先启动 `db` 并等待健康检查通过，再启动 `app`。镜像里的 `HEALTHCHECK` 指令在 Compose 中同样生效，配置文件中的 `healthcheck` 可以覆盖它。

## 常用命令

| 命令                                 | 作用                |
|------------------------------------|-------------------|
| `docker compose up -d`             | 创建并后台启动全部服务       |
| `docker compose ps`                | 查看项目内容器状态         |
| `docker compose logs -f <service>` | 跟随查看服务日志          |
| `docker compose exec <service> sh` | 进入服务容器            |
| `docker compose config`            | 校验并输出最终合并的配置      |
| `docker compose down`              | 停止并删除容器和默认网络      |
| `docker compose down -v`           | 额外删除配置中声明的命名卷和匿名卷 |

`down` 默认就会删除容器和项目网络，但保留卷；`down -v` 连同数据卷一起删除，涉及业务数据时执行前必须确认备份。标记为 `external` 的网络和卷不由 Compose 管理，任何情况下都不会被删除。

## 与 Kubernetes 的边界

Compose 面向单机多容器编排：一台主机、一个 Docker daemon。它不提供多节点调度、自愈副本和滚动更新，这些是 Kubernetes 工作负载控制器的职责。学习价值在于概念映射：`services` 近似 Deployment 加 Service 的组合，`healthcheck` 对应探针，`depends_on` 的就绪语义在 Kubernetes 中由 Init Container 和 readinessProbe 表达。Compose 配置不能直接迁移到 Kubernetes，但对“声明式描述一组服务”的理解是共通的。

## 记录要点

- 新项目统一使用 `compose.yaml` 文件名和 `docker compose` 命令，不再写顶层 `version` 字段。
- 服务间访问使用服务名，不硬编码容器 IP 或宿主机端口。
- 依赖数据库等慢启动服务时，用 `healthcheck` 加 `condition: service_healthy`，不要依赖启动顺序碰运气。
- `down -v` 会删除数据卷，日常停启使用 `docker compose stop` 和 `docker compose up -d`。
- 敏感配置通过 `secrets` 或环境文件注入，不直接写入 `compose.yaml` 提交到仓库。

## 参考

- [Docker Compose overview](https://docs.docker.com/compose/)
- [Compose file reference](https://docs.docker.com/reference/compose-file/)
- [Compose 应用模型](https://docs.docker.com/compose/intro/compose-application-model/)
- [Control startup and shutdown order](https://docs.docker.com/compose/how-tos/startup-order/)
- [Networking in Compose](https://docs.docker.com/compose/how-tos/networking/)
- [docker compose CLI](https://docs.docker.com/reference/cli/docker/compose/)
