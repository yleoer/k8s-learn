# Docker Compose 基础

[上一篇](./6-Docker网络与容器间通信.md)已经验证了自定义 bridge 网络和容器名 DNS 解析，但网络创建、启动顺序、端口和挂载参数仍然分散在多条 `docker run` 命令中，服务数量增加后很快难以维护。Docker Compose 用一个 `compose.yaml` 文件描述一组相关容器、网络、卷、配置和敏感数据，再通过 `docker compose` 命令统一创建、更新、查看和销毁这些资源。

Compose 文件本身不直接运行容器：Compose CLI 先把它解析成应用模型，再调用 Docker Engine 创建容器、网络和卷。本篇记录单机多容器应用的基础用法，后续理解 Kubernetes 工作负载、Service、配置注入和存储挂载时，可以把 Compose 作为一个更小范围的对照。

## Compose 解决的问题

`docker run` 适合启动单个容器，也适合快速验证镜像行为；当一个应用由 Web 服务、数据库、缓存、消息队列、调试容器等多个组件组成时，手写命令会带来几个问题：

- 每个服务的镜像、端口、挂载、环境变量和重启策略分散在命令历史中。
- 容器之间需要加入同一个网络，并约定稳定的访问名称。
- 数据卷和 bind mount 需要人工创建、复用和清理。
- 服务之间存在依赖关系，数据库等组件可能已经启动容器但尚未就绪。
- 不同环境需要少量差异配置，直接复制整套命令容易产生偏差。

Compose 适合单机多容器应用、本地开发环境、集成验证环境和服务依赖验证。它不负责多节点调度、集群级服务发现、控制器自愈、滚动发布和入口流量管理，因此不是 Kubernetes 的替代品。

## 版本形态

Compose 有两条容易混淆的版本线：一条是 Compose CLI 自身的版本，另一条是 Compose 文件格式的历史版本。

当前受官方支持的 Compose CLI 版本是 Compose v2 和 Compose v5，两者都按 Compose Specification 解释配置文件：

| 形态 | 实现与命令 | 状态与边界 |
| --- | --- | --- |
| Compose v1 | Python 实现，命令为 `docker-compose` | 2014 年发布，已不在受支持版本之列。旧项目常见顶层 `version` 字段，取值从 `2.0` 到 `3.8`。 |
| Compose v2 | Go 实现，命令为 `docker compose` | 2020 年发布，作为 Docker CLI 插件使用。忽略顶层 `version` 字段，完全按 Compose Specification 解释文件。 |
| Compose v5 | Go 实现，命令仍为 `docker compose` | 2025 年发布，功能与 Compose v2 保持一致，主要区别是引入官方 Go SDK。版本号直接跳到 v5，是为了避免与旧文件格式的 2.x、3.x 混淆。 |

Compose 文件格式在 v1 时代先后发布过三个大版本：file format 1（2014）、file format 2.x（2016）和 file format 3.x（2017）。file format 1 没有顶层 `services` 键，与后续格式差异很大，写成这种格式的文件无法在 Compose v2/v5 上运行；2.x 和 3.x 较为接近，3.x 主要为 Swarm 部署增加了选项。为了消除 CLI 版本、文件格式版本和 Swarm 功能差异带来的混乱，2.x 和 3.x 已合并为滚动更新的 Compose Specification，顶层 `version` 字段随之变为可选并废弃。Compose v2/v5 对 2.x/3.x 中已弃用或调整过的元素保留向后兼容。

> [!NOTE]
> 新写 Compose 文件时不再添加顶层 `version` 字段。该字段只为兼容旧文件保留，写了会收到废弃警告；无论写什么值，Compose 都按最新的 Compose Specification 校验文件。

## 安装与版本确认

Docker Desktop 是官方推荐的安装方式，它自带 Docker Engine、Docker CLI 和 Docker Compose。Linux 上如果已经安装 Docker Engine 与 Docker CLI，可以单独安装 `docker-compose-plugin` 包，这种插件安装方式仅适用于 Linux。standalone 独立二进制只为向后兼容保留，不是新环境的推荐方式。

确认当前 Compose CLI 版本：

```bash
docker compose version
```

::: details 版本输出类似如下

```text
Docker Compose version v5.2.0
```

:::

如果命令提示 `docker: 'compose' is not a docker command`，通常表示当前 Docker CLI 没有安装 Compose plugin，或者 Docker Desktop 未正确启动。

## 应用模型

Compose 把一组容器相关资源组织成一个 project。project 是同一份应用声明在某个 Docker 环境中的一次部署实例，项目名会作为前缀参与容器、网络和卷等资源的命名；同一份 `compose.yaml` 只要换一个项目名，就可以在同一台主机上部署第二份互不干扰的副本。

常见对象关系如下：

| 对象 | 含义 |
| --- | --- |
| `project` | 一次 Compose 应用部署。项目名影响默认网络 `<project>_default`、命名卷和自动生成的容器名。 |
| `service` | 一类同构容器的声明，例如 `web`、`db`、`cache`。同一服务由同一镜像和同一组运行参数创建，可以运行一个或多个容器。 |
| `network` | 服务之间通信的网络边界，为相互连接的服务容器建立 IP 路由。未显式声明时，Compose 会创建默认 bridge 网络。 |
| `volume` | Docker 管理的持久化数据卷，适合数据库数据、应用状态和需要跨容器生命周期保留的数据。 |
| `config` | 非敏感配置数据，以文件形式挂载到容器内，容器内的表现与卷类似。 |
| `secret` | 面向敏感数据的配置对象，服务必须显式引用后才能访问，默认挂载到 `/run/secrets/<secret_name>`。 |

项目名的优先级从高到低为：

1. `docker compose -p <project>` 或 `--project-name <project>`。
2. `COMPOSE_PROJECT_NAME` 环境变量。
3. Compose 文件顶层 `name`；用 `-f` 指定多个文件时，取最后一个文件的 `name`。
4. Compose 文件所在目录名；用 `-f` 指定多个文件时，取第一个文件所在目录名。
5. 未指定 Compose 文件时的当前目录名。

项目名只能包含小写字母、数字、短横线和下划线，并且需要以小写字母或数字开头。为了减少不同目录名带来的差异，本篇示例统一在 `compose.yaml` 中显式写入顶层 `name`。项目名确定后，会以 `COMPOSE_PROJECT_NAME` 变量暴露给配置文件插值使用。

## 配置文件

Compose 默认在当前工作目录查找 `compose.yaml`（首选）或 `compose.yml`。为了兼容旧项目，它仍然支持 `docker-compose.yaml` 和 `docker-compose.yml`；如果同时存在，优先使用标准文件名 `compose.yaml`。

常见顶层元素如下：

| 顶层元素 | 作用 |
| --- | --- |
| `name` | 指定项目名。 |
| `services` | 定义服务，是 Compose 文件的核心。 |
| `networks` | 定义自定义网络；未声明时使用默认网络。 |
| `volumes` | 定义命名卷。 |
| `configs` | 定义非敏感配置对象。 |
| `secrets` | 定义敏感数据对象。 |

## 最小服务组

下面示例包含两个服务：

- `web`：使用 nginx 发布静态页面，把宿主机 `./html` 目录以只读方式挂载到容器内。
- `client`：使用 Alpine 容器作为网络验证客户端，通过服务名 `web` 访问 nginx。

准备目录和页面文件：

```bash
mkdir -p compose-basic/html
cd compose-basic
printf 'hello compose\n' > html/index.html
```

```yaml [compose.yaml]
name: compose-basic

services:
  web:
    image: nginx:1.31-alpine
    ports:
      - "8080:80"
    volumes:
      - ./html:/usr/share/nginx/html:ro
    restart: unless-stopped

  client:
    image: alpine:3.23
    command: ["sh", "-c", "sleep 365d"]
    depends_on:
      - web
```

启动服务组并查看状态：

```bash
docker compose up -d
docker compose ps
```

::: details 状态输出类似如下

```text
NAME                     IMAGE               COMMAND                  SERVICE   CREATED          STATUS         PORTS
compose-basic-client-1   alpine:3.23         "sh -c 'sleep 365d'"     client    3 seconds ago   Up 2 seconds
compose-basic-web-1      nginx:1.31-alpine   "/docker-entrypoint.…"   web       3 seconds ago   Up 3 seconds   0.0.0.0:8080->80/tcp, [::]:8080->80/tcp
```

:::

从宿主机访问发布端口：

```bash
curl http://127.0.0.1:8080
```

::: details 输出类似如下

```text
hello compose
```

:::

从 `client` 容器内通过服务名访问 `web`：

```bash
docker compose exec client wget -qO- http://web
```

::: details 输出类似如下

```text
hello compose
```

:::

清理容器和默认网络：

```bash
docker compose down
```

这个示例中，宿主机访问 nginx 使用 `127.0.0.1:8080`，容器之间访问 nginx 使用 `http://web:80` 或简写 `http://web`。两者端口语义不同，后面的网络章节会单独记录。

## 服务字段

`services` 下每个键都是服务名。服务名不仅用于配置引用，也会成为默认网络内的 DNS 名称。

| 字段 | 作用 |
| --- | --- |
| `image` | 指定服务使用的镜像。 |
| `build` | 指定构建上下文和 Dockerfile，用源码构建镜像。可以和 `image` 配合，为构建结果指定镜像名。 |
| `command` | 覆盖镜像默认 `CMD`，适合调整启动参数。 |
| `entrypoint` | 覆盖镜像默认 `ENTRYPOINT`。会改变容器启动入口，使用前需要确认镜像启动逻辑。 |
| `ports` | 发布容器端口到宿主机，常见格式为 `"HOST_PORT:CONTAINER_PORT"`。 |
| `expose` | 仅声明容器端口，不发布到宿主机；同一网络内服务仍通过容器端口访问。 |
| `environment` | 直接向容器注入环境变量，支持映射或列表语法。 |
| `env_file` | 从文件向容器注入环境变量，适合复用较长的环境变量列表。 |
| `volumes` | 挂载 bind mount、命名卷或匿名卷。 |
| `networks` | 指定服务加入哪些网络；未设置时加入默认网络。 |
| `depends_on` | 表达服务启动和停止顺序；长格式可结合健康检查等待依赖就绪。 |
| `healthcheck` | 定义容器健康检查命令、间隔、超时和重试次数。 |
| `restart` | 定义容器退出后的重启策略：`no`（默认，从不重启）、`always`、`on-failure[:max-retries]`、`unless-stopped`。 |
| `profiles` | 把服务放入可选 profile，只有 profile 启用时才启动该服务。 |
| `secrets` | 声明服务可以访问哪些顶层 `secrets`。 |
| `pull_policy` | 控制镜像拉取策略，常见取值有 `missing`（默认）、`always`、`never`、`build`。 |

通常不建议固定 `container_name`。Compose 默认生成的容器名包含项目名、服务名和序号，便于同一项目多副本运行；如果设置 `container_name`，该服务无法扩展到多个容器，尝试扩容会直接报错，项目之间也更容易出现名称冲突。

## 网络与端口

未显式定义网络时，`docker compose up` 会创建一个名为 `<project>_default` 的 bridge 网络。项目内所有服务默认加入该网络，服务名注册到 Docker 内部 DNS，容器之间直接用服务名互访即可，不需要关心 IP 地址。

容器 IP 从网络子网中动态分配，重启或重建后会变化；配置变更后执行 `docker compose up`，旧容器被移除，新容器以相同的服务名、不同的 IP 加入网络，指向旧容器的已有连接会被关闭，由应用自行重新解析并重连。因此服务间引用应始终使用服务名，不要记录容器 IP。

`ports` 的短语法为 `[HOST:]CONTAINER[/PROTOCOL]`：`HOST` 可以带绑定地址和端口（或端口区间），省略时容器端口发布到宿主机的随机可用端口；`PROTOCOL` 默认 `tcp`。宿主机访问使用发布端口，服务间通信使用容器端口，这是两个不同的入口。

> [!WARNING]
> `ports` 不指定宿主机绑定地址时，Docker 默认绑定所有网卡（`0.0.0.0`），并且会绕过宿主机防火墙规则。宿主机有公网地址时，容器端口可能直接暴露到互联网；只在本机使用的端口应显式写成 `"127.0.0.1:8080:80"` 这样的形式。

需要更细的网络边界时，可以用顶层 `networks` 定义多个网络，再在服务级 `networks` 中声明加入关系。下面示例中 `proxy` 与 `db` 不在同一网络，互相不可见，只有 `app` 能同时访问两侧：

```yaml [compose.yaml]
name: compose-topology

services:
  proxy:
    image: nginx:1.31-alpine
    ports:
      - "8080:80"
    networks:
      - frontend

  app:
    image: alpine:3.23
    command: ["sh", "-c", "sleep 365d"]
    networks:
      - frontend
      - backend

  db:
    image: postgres:18.4
    environment:
      POSTGRES_PASSWORD: example
    networks:
      - backend

networks:
  frontend:
  backend:
```

启动后验证网络隔离：`app` 能解析两侧服务名，`proxy` 解析不到 `db`：

```bash
docker compose up -d
docker compose exec app nslookup db
docker compose exec proxy nslookup db
```

::: details 第二条命令输出类似如下

```text
nslookup: can't resolve 'db': Name does not resolve
```

:::

如果要连接 Compose 之外用 `docker network create` 创建的网络，可以在顶层网络上声明 `external: true` 并指定 `name`；外部网络必须在 `docker compose up` 之前存在，否则报 `Network not found`。不同 project 的服务加入同一个外部网络后，也可以通过服务名互访。

常用排查命令：

```bash
docker compose port web 80
docker network inspect compose-topology_frontend
docker compose exec app nslookup proxy
docker compose exec app wget -qO- http://proxy
```

::: details 端口查询输出类似如下

```text
0.0.0.0:8080
```

:::

> [!NOTE]
> `ports` 发布端口给宿主机或外部访问；服务之间在同一个 Compose 网络中通信时，应使用服务名和容器端口，不应绕到宿主机发布端口。

## 数据卷与挂载

服务级 `volumes` 的短语法为 `VOLUME:CONTAINER_PATH[:ACCESS_MODE]`：`VOLUME` 是宿主机路径（bind mount）或卷名，访问模式默认 `rw`，可写 `ro` 限制为只读。bind mount 的相对路径从 Compose 文件所在目录解析。三类挂载的差异在[持久化与服务部署](./5-持久化与服务部署.md)中已有展开，这里从 Compose 视角对比：

| 类型 | 示例 | 适用场景 | 边界 |
| --- | --- | --- | --- |
| bind mount | `./html:/usr/share/nginx/html:ro` | 源码、静态文件、开发配置从宿主机直接挂入容器。 | 依赖宿主机目录结构，默认可写，建议按需加 `:ro`。 |
| named volume | `db-data:/var/lib/postgresql` | 数据库数据、应用状态等由 Docker 管理的持久化数据。跨服务复用时必须在顶层 `volumes` 声明。 | 不方便直接从宿主机目录编辑，但更适合跨容器生命周期保留。 |
| anonymous volume | `/var/lib/postgresql` | 镜像 `VOLUME` 指令或省略卷名时隐式产生的数据目录。 | 名称随机，后续 `up` 不会自动复用，不适合存放需要保留的数据。 |

`docker compose down` 默认删除本项目的容器和网络，保留命名卷，匿名卷也不会删除；但匿名卷没有稳定名称，重建后的容器不会自动挂回原来的匿名卷，需要保留的数据应使用命名卷或 bind mount。声明为 `external` 的网络和卷永远不会被 `down` 删除。`docker compose down -v` 会额外删除 Compose 文件 `volumes` 中声明的命名卷，以及容器挂载的匿名卷。

> [!WARNING]
> 对数据库、对象存储、消息队列等有状态服务执行 `docker compose down -v` 前，需要确认数据已经备份。这个命令会删除命名卷和匿名卷，不能当作普通停止命令使用。

named volume 示例：

```yaml [compose.yaml]
name: compose-volume

services:
  db:
    image: postgres:18.4
    environment:
      POSTGRES_DB: app
      POSTGRES_USER: app
      POSTGRES_PASSWORD: example
    volumes:
      - db-data:/var/lib/postgresql
    restart: unless-stopped

volumes:
  db-data:
```

启动并查看卷：

```bash
docker compose up -d
docker compose exec db psql -U app -d app -c "select current_database();"
docker volume ls
docker volume inspect compose-volume_db-data
```

普通停止并保留数据：

```bash
docker compose down
```

需要连同示例数据一起清理时，再使用：

```bash
docker compose down -v
```

## 环境变量与配置

Compose 中的环境变量有两类用途，需要分开看：

- shell 环境变量和 `.env` 文件用于 Compose 文件插值，在解析配置时替换 `${NGINX_TAG}`、`${WEB_PORT}` 这样的占位。
- `environment` 和 `env_file` 用于把环境变量注入容器进程。

插值支持 `$VAR` 和 `${VAR}` 两种写法，只作用于不带引号和双引号的值，单引号值不做插值。花括号形式还支持默认值和校验：

| 写法 | 含义 |
| --- | --- |
| `${VAR:-default}` | `VAR` 已设置且非空时取其值，否则取 `default`。 |
| `${VAR-default}` | `VAR` 已设置时取其值（含空值），否则取 `default`。 |
| `${VAR:?error}` | `VAR` 未设置或为空时报错退出，错误信息为 `error`。 |
| `${VAR:+replacement}` | `VAR` 已设置且非空时取 `replacement`，否则为空。 |

需要向容器传入字面 `$` 时写成 `$$`，避免被 Compose 当作插值处理。同一个变量在多个插值来源中出现时，shell 环境变量优先于 `--env-file` 指定的文件，`--env-file` 优先于项目目录中的 `.env`。

`.env` 默认放在项目目录中，通常与 `compose.yaml` 同级。它不会因为存在就自动进入容器，只有被 Compose 文件插值引用，或者通过 `env_file` 声明时，相关值才会进入容器环境。

```text [.env]
NGINX_TAG=1.31-alpine
WEB_PORT=8080
APP_MODE=dev
```

```text [web.env]
NGINX_ENTRYPOINT_QUIET_LOGS=1
```

```yaml [compose.yaml]
name: compose-env

services:
  web:
    image: "nginx:${NGINX_TAG:-1.31-alpine}"
    ports:
      - "${WEB_PORT:-8080}:80"
    environment:
      APP_MODE: "${APP_MODE:-dev}"
    env_file:
      - ./web.env
```

`environment` 支持映射和列表两种语法；列表条目只写变量名不写值时（例如 `- DEBUG`），Compose 会把当前 shell 中的同名变量直接透传给容器。`env_file` 的路径相对于 Compose 文件所在目录解析，可以声明多个文件，按顺序求值，后面的文件覆盖前面的同名变量；较新版本还支持 `required: false`，文件缺失时跳过而不报错。

同一个变量在多处定义时，容器内最终值按以下优先级决定（从高到低）：

1. `docker compose run -e` 在命令行显式设置的值。
2. `environment` 或 `env_file` 中通过插值从 shell 或 `.env` 取到的值。
3. `environment` 中直接写死的值。
4. `env_file` 文件中的值。
5. 镜像 `ENV` 指令设置的值。

排查时先看插值结果，再看容器实际环境：

```bash
docker compose config
docker compose config --environment
docker compose up -d
docker compose exec web env
```

`docker compose config` 输出合并、插值后的最终配置模型，`--environment` 列出参与插值的变量。

> [!CAUTION]
> 不要把真实密码、Token、私有仓库凭据或生产连接串提交到 `.env`、`env_file` 或 `compose.yaml`。需要提交的示例值应使用 `example`、`<registry.example.com>`、`<namespace>` 等占位值。

## secrets

Compose secrets 适合向容器传递密码、证书、API key 等敏感数据。相比环境变量，secrets 以文件形式挂载到容器内（默认路径 `/run/secrets/<secret_name>`），可以用文件权限做细粒度控制，也避免敏感值随环境变量泄漏到日志或子进程。

使用分两步：先在顶层 `secrets` 定义数据来源，再在服务的 `secrets` 字段中显式引用。顶层来源有两种：`file` 读取指定文件的内容，`environment` 读取宿主机环境变量的值。服务不引用就无法访问，授权按服务粒度生效。

下面示例使用 MySQL 镜像支持的 `_FILE` 环境变量约定，让 MySQL 从 secret 文件读取密码：

```bash
mkdir -p secrets
printf 'example-root-password\n' > secrets/mysql_root_password.txt
printf 'example-app-password\n' > secrets/mysql_app_password.txt
```

```yaml [compose.yaml]
name: compose-secret

services:
  db:
    image: mysql:8.4
    environment:
      MYSQL_DATABASE: app
      MYSQL_USER: app
      MYSQL_PASSWORD_FILE: /run/secrets/mysql_app_password
      MYSQL_ROOT_PASSWORD_FILE: /run/secrets/mysql_root_password
    secrets:
      - mysql_app_password
      - mysql_root_password
    volumes:
      - mysql-data:/var/lib/mysql

secrets:
  mysql_app_password:
    file: ./secrets/mysql_app_password.txt
  mysql_root_password:
    file: ./secrets/mysql_root_password.txt

volumes:
  mysql-data:
```

启动后可以查看容器内的 secret 文件路径：

```bash
docker compose up -d
docker compose exec db ls -l /run/secrets
```

> [!NOTE]
> `_FILE` 是 MySQL、PostgreSQL 等部分官方镜像约定的环境变量读取方式，不是 Compose 自动转换环境变量的机制。Compose 只负责把 secret 文件挂载到容器内，应用或镜像必须自己读取这个文件。

本地记录中可以把 `secrets/*.txt` 加入 `.gitignore`，只提交 `compose.yaml` 和必要的占位说明。

## 启动顺序与健康检查

`depends_on` 决定服务的创建、启动和删除顺序：依赖服务先创建启动，删除时反向进行。短格式只保证依赖容器已经启动（started），不保证依赖服务已经可以处理请求。数据库、缓存、消息队列等服务常常需要额外初始化时间，应用容器如果只依赖短格式 `depends_on`，仍可能在启动时连接失败。

等待依赖就绪时，应给依赖服务定义 `healthcheck`，并在 `depends_on` 长格式中使用 `condition: service_healthy`：

```yaml [compose.yaml]
name: compose-health

services:
  app:
    image: alpine:3.23
    command: ["sh", "-c", "echo db is healthy; sleep 365d"]
    depends_on:
      db:
        condition: service_healthy
        restart: true

  db:
    image: postgres:18.4
    environment:
      POSTGRES_DB: app
      POSTGRES_USER: app
      POSTGRES_PASSWORD: example
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 10s
      timeout: 10s
      retries: 5
      start_period: 30s
```

`healthcheck.test` 中的 `$$` 是插值转义，让 `POSTGRES_USER` 等变量留到容器内再由 shell 展开。运行和观察：

```bash
docker compose up -d
docker compose ps
docker compose logs app
```

`depends_on` 长格式的常用字段：

| 字段 | 含义 |
| --- | --- |
| `condition: service_started` | 依赖容器已启动，语义等同短格式。 |
| `condition: service_healthy` | 依赖服务的健康检查通过后，再启动当前服务。 |
| `condition: service_completed_successfully` | 依赖服务成功运行结束后，再启动当前服务，适合一次性初始化任务。 |
| `restart: true` | 依赖服务被 Compose 操作显式更新或重启时，当前服务随之自动重启；容器运行时的自动重启不触发该行为。Compose 2.17.0 引入。 |
| `required: false` | 依赖服务未启动或不可用时只发出警告，不阻止当前服务启动，默认 `true`。Compose 2.20.0 引入。 |

`healthcheck` 与 Dockerfile 的 `HEALTHCHECK` 指令语义一致，Compose 文件中的定义会覆盖镜像内置的检查。`test` 用列表形式时第一项必须是 `CMD`、`CMD-SHELL` 或 `NONE`；直接写字符串等价于 `CMD-SHELL`。除 `interval`、`timeout`、`retries`、`start_period` 外，较新版本还支持 `start_interval` 控制启动阶段的探测间隔；`disable: true` 可以关闭镜像自带的健康检查。

> [!TIP]
> `healthcheck` 表达的是容器内应用是否达到可用状态，检查命令应尽量使用服务自身提供的探测工具，例如 PostgreSQL 的 `pg_isready`、HTTP 服务的健康检查路径或消息队列的管理命令。

## profiles 与多文件

### profiles

profiles 用于把调试工具、管理界面、一次性任务等可选服务放在同一份 Compose 文件中。未配置 `profiles` 的核心服务始终启用；配置了 `profiles` 的服务只在对应 profile 激活时参与启动和停止。profile 名称需要匹配 `[a-zA-Z0-9][a-zA-Z0-9_.-]+`。

```yaml [compose.yaml]
name: compose-profile

services:
  web:
    image: nginx:1.31-alpine
    ports:
      - "8080:80"

  shell:
    image: alpine:3.23
    command: ["sh", "-c", "sleep 365d"]
    profiles:
      - debug
```

默认只启动核心服务：

```bash
docker compose up -d
```

启动调试 profile，`--profile` 参数和 `COMPOSE_PROFILES` 环境变量等价：

```bash
docker compose --profile debug up -d
COMPOSE_PROFILES=debug docker compose up -d
docker compose exec shell sh
```

在命令行显式指定带 profile 的服务时（例如 `docker compose run shell`），Compose 会自动启用该服务及其 `depends_on` 依赖，不需要手动加 `--profile`，适合一次性任务。停止 profile 服务时同样需要带上 `--profile`，否则 `docker compose down` 只处理核心服务。

> [!NOTE]
> 核心服务不应放入 profile，否则普通 `docker compose up` 可能启动不完整的应用。

### 多文件合并

多文件适合保留一份基础配置，再叠加开发、测试或临时排查配置。不加 `-f` 时，Compose 除了 `compose.yaml` 还会自动加载同目录下的 `compose.override.yaml`（如果存在）并合并；用 `-f` 显式指定多个文件时，按命令行顺序依次合并，后面的文件覆盖或补充前面的内容。

覆盖文件可以只包含需要调整的片段，不必是完整的 Compose 文件。下面是一份基础文件和一份开发覆盖文件：

```yaml [compose.yaml]
name: compose-merge

services:
  web:
    image: nginx:1.31-alpine
    ports:
      - "8080:80"
    environment:
      APP_MODE: prod
```

```yaml [compose.dev.yaml]
services:
  web:
    environment:
      APP_MODE: dev
    volumes:
      - ./html:/usr/share/nginx/html:ro
```

合并并查看最终配置：

```bash
docker compose -f compose.yaml -f compose.dev.yaml config
```

合并规则按字段类型区分：

- `image`、`command` 等单值字段：后面的文件直接替换前面的值。
- `ports`、`expose`、`dns`、`tmpfs` 等列表字段：两边的值拼接。
- `environment`、`labels`：按变量名或标签名合并，后面的文件优先。
- `volumes`、`devices`：按容器内挂载路径合并，后面的文件优先。

所有相对路径都基于第一个 Compose 文件所在目录解析，覆盖文件中的相对路径不会按自身位置解析；端口、挂载、环境变量等合并结果不符合预期时，先用 `docker compose -f ... config` 查看最终模型。如果希望每个文件的路径按各自目录解析，或要复用其他团队维护的 Compose 应用，可以改用顶层 `include` 元素。

## 常用命令

| 命令 | 作用 |
| --- | --- |
| `docker compose up -d` | 创建并后台启动服务。配置变化时会按需重建容器。 |
| `docker compose down` | 停止并删除本项目容器和网络，默认保留卷。 |
| `docker compose stop` | 停止服务，保留容器、网络和卷。 |
| `docker compose start` | 启动已经存在但处于停止状态的服务容器。 |
| `docker compose restart` | 重启服务。 |
| `docker compose ps` | 查看服务容器状态和端口映射。 |
| `docker compose logs -f <service>` | 跟随查看指定服务日志。 |
| `docker compose exec <service> sh` | 在运行中的服务容器内执行命令。 |
| `docker compose run --rm <service> <cmd>` | 基于服务配置启动一次性容器执行命令。 |
| `docker compose config` | 校验并输出合并、插值后的 Compose 配置。 |
| `docker compose port <service> <port>` | 查看容器端口对应的宿主机发布地址。 |
| `docker compose pull` | 拉取服务镜像。 |
| `docker compose build` | 构建包含 `build` 配置的服务镜像。 |

日常停启有状态服务时，优先使用 `docker compose stop`、`docker compose start` 或 `docker compose up -d`。只有确认要删除容器和项目网络时，再使用 `docker compose down`；只有确认要删除数据卷时，再使用 `docker compose down -v`。

## 常见排查

| 现象 | 排查方向 |
| --- | --- |
| 端口占用导致服务启动失败 | 检查 `ports` 的宿主机端口是否已经被其他进程或容器占用。可以改用其他宿主机端口，或只写容器端口让 Docker 动态分配，再用 `docker compose port <service> <container-port>` 查看实际端口。 |
| 服务名解析失败 | 确认两个服务属于同一 project，并加入同一个网络。使用 `docker network inspect <project>_default` 查看网络成员。 |
| 容器内能访问，宿主机不能访问 | 检查是否配置了 `ports`。`expose` 不会发布端口到宿主机。 |
| 宿主机能访问，服务间访问失败 | 服务间访问应使用服务名和容器端口，例如 `http://web:80`，不是宿主机发布端口。 |
| 卷数据不符合预期 | 区分 bind mount 和 named volume。bind mount 依赖宿主机路径，named volume 由 Docker 管理。使用 `docker volume inspect` 确认卷名称和挂载来源。 |
| `down -v` 后数据丢失 | `down -v` 会删除 Compose 文件声明的命名卷和匿名卷。恢复依赖外部备份，后续应避免把它作为普通停止命令。 |
| 健康检查一直失败 | 查看 `docker compose ps` 的健康状态和 `docker compose logs <service>` 日志，进入容器手动执行 `healthcheck.test` 中的命令。 |
| 多文件合并结果不符合预期 | 使用 `docker compose -f compose.yaml -f compose.dev.yaml config` 查看最终配置，重点检查列表字段拼接、映射字段覆盖和相对路径解析；确认是否有 `compose.override.yaml` 被自动加载。 |
| 环境变量没有注入容器 | 区分 `.env` 插值和 `env_file` 注入。用 `docker compose config --environment` 查看插值变量，用 `docker compose exec <service> env` 查看容器环境。 |
| secret 文件不存在或权限异常 | 确认顶层 `secrets` 的 `file` 路径存在，并确认服务自身 `secrets` 字段显式引用了该 secret。 |
| PostgreSQL 18+ 提示 `/var/lib/postgresql/data (unused mount/volume)` | 检查是否仍把卷挂载到旧路径 `/var/lib/postgresql/data`。`postgres:18.4` 及更高版本应挂载 `/var/lib/postgresql`；已有真实数据时不能直接删除卷，需要按 PostgreSQL 大版本升级流程迁移。 |

## 与 Kubernetes 的边界

Compose 面向单机 Docker 环境，核心对象是 service、network、volume、config 和 secret。它适合把一组容器放在同一台主机上运行，并用声明式文件保存运行参数。

Kubernetes 面向集群环境，核心能力包括多节点调度、控制器持续对账、副本自愈、滚动更新、Service 抽象、Ingress 或 Gateway 入口、命名空间、准入控制和更完整的存储编排。Compose 的 `restart` 可以让单个容器按策略重启，但它不等价于 Kubernetes 控制器的期望状态管理。

在本仓库的记录脉络中，Compose 更适合作为理解声明式服务组、服务名访问、端口发布、挂载和配置注入的过渡。进入 Kubernetes 后，需要重新理解 Pod、Deployment、Service、ConfigMap、Secret、PV、PVC 等对象的职责边界。

## 记录要点

- 新项目使用 `compose.yaml` 和 `docker compose`，不再新写顶层 `version` 字段。
- Compose CLI 的 v2/v5 与旧 Compose file format 2.x/3.x 不是同一条版本线，当前受支持的 CLI 版本是 v2 和 v5。
- 服务之间通过服务名和容器端口访问，不依赖容器 IP，也不绕到宿主机发布端口。
- 只在本机使用的发布端口应显式绑定 `127.0.0.1`，避免默认 `0.0.0.0` 绑定把端口暴露给外部。
- 修改 Compose 文件后，先用 `docker compose config` 查看合并、插值后的最终配置。
- 慢启动依赖使用 `healthcheck` 加 `depends_on.condition: service_healthy` 表达就绪关系。
- `docker compose down` 默认保留卷，`docker compose down -v` 会删除命名卷和匿名卷。
- 不加 `-f` 时，`compose.override.yaml` 会被自动加载并合并进 `compose.yaml`。
- Compose 是单机多容器编排工具，不替代 Kubernetes 的集群编排能力。

## 参考

- [Docker Compose](https://docs.docker.com/compose/)
- [History and development of Docker Compose](https://docs.docker.com/compose/intro/history/)
- [How Compose works](https://docs.docker.com/compose/intro/compose-application-model/)
- [Overview of installing Docker Compose](https://docs.docker.com/compose/install/)
- [Compose file reference](https://docs.docker.com/reference/compose-file/)
- [Version and name top-level elements](https://docs.docker.com/reference/compose-file/version-and-name/)
- [Define services in Docker Compose](https://docs.docker.com/reference/compose-file/services/)
- [Secrets top-level element](https://docs.docker.com/reference/compose-file/secrets/)
- [Specify a project name](https://docs.docker.com/compose/how-tos/project-name/)
- [Networking in Compose](https://docs.docker.com/compose/how-tos/networking/)
- [Control startup and shutdown order in Compose](https://docs.docker.com/compose/how-tos/startup-order/)
- [Set environment variables within your container's environment](https://docs.docker.com/compose/how-tos/environment-variables/set-environment-variables/)
- [Set, use, and manage variables in a Compose file with interpolation](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/)
- [Environment variables precedence in Docker Compose](https://docs.docker.com/compose/how-tos/environment-variables/envvars-precedence/)
- [Using profiles with Compose](https://docs.docker.com/compose/how-tos/profiles/)
- [Merge Compose files](https://docs.docker.com/compose/how-tos/multiple-compose-files/merge/)
- [Manage secrets securely in Docker Compose](https://docs.docker.com/compose/how-tos/use-secrets/)
- [docker compose config](https://docs.docker.com/reference/cli/docker/compose/config/)
- [docker compose down](https://docs.docker.com/reference/cli/docker/compose/down/)
- [Volumes](https://docs.docker.com/engine/storage/volumes/)
- [Bind mounts](https://docs.docker.com/engine/storage/bind-mounts/)
- [Postgres Docker Official Image](https://github.com/docker-library/docs/blob/master/postgres/README.md)
