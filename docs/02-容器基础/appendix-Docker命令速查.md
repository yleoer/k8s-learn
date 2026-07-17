# Docker 命令速查

本附录按对象和场景汇总本章使用的高频 Docker 命令。正文解释概念、边界与完整操作流程；附录用于检索语法、常用参数和风险点，命令与正文保持相同的版本和操作语义。

> [!NOTE]
> Docker 命令按 Docker Engine 29.6.1 与随发行版提供的 Docker CLI 整理，核验日期为 2026-07-15。Compose 命令按 Docker Compose v5.3.1 整理。Docker Desktop、rootless 模式和发行版打包版本可能不同，执行前先运行 `docker version`、`docker info` 和 `docker compose version`。

对象化写法为 `docker <object> <command>`，例如 `docker container ls`、`docker image pull`。`docker ps`、`docker images`、`docker pull`、`docker run` 等短写法仍是官方别名。本附录优先使用对象化写法；需要低频参数和完整选项时，先执行 `docker <object> <command> --help`，再查阅文末官方参考。

## 环境与上下文

```bash
docker version
docker version --format '{{.Server.Version}}'
docker info
docker info --format '{{.Driver}}'
docker context ls
docker context use default
docker context inspect default
docker system df -v
docker events --filter type=container
```

| 命令 | 常用参数 | 作用 |
| --- | --- | --- |
| `docker version` | `--format` | 查看 Client 与 Server 版本；仅有 Client 通常表示 Daemon 未启动或无权访问。 |
| `docker info` | `--format` | 查看存储、日志、cgroup、Registry Mirrors 等环境信息。 |
| `docker context ls/use/inspect` | 无 | 列出、切换、检查 Docker Daemon 连接；切换前确认不是生产环境。 |
| `docker system df` | `-v`、`--verbose` | 查看镜像、容器、卷与构建缓存占用，清理前先执行。 |
| `docker events` | `--filter`、`--since`、`--until` | 持续查看对象事件，适合关联容器退出与网络连接时间点。 |

Linux 主机无法连接 Daemon 时：

```bash
sudo systemctl status docker --no-pager
sudo journalctl -u docker -xe --no-pager
ls -l /var/run/docker.sock
id
```

## 镜像

```bash
docker search nginx
docker image pull nginx:1.31-alpine
docker image pull --platform linux/arm64 nginx:1.31-alpine
docker image ls --digests --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}'
docker image inspect nginx:1.31-alpine
docker image history --no-trunc nginx:1.31-alpine
docker image tag nginx:1.31-alpine nginx:demo
docker image save -o nginx-1.31-alpine.tar nginx:1.31-alpine
docker image load -i nginx-1.31-alpine.tar
```

| 命令 | 常用参数 | 作用 |
| --- | --- | --- |
| `docker search <term>` | `--filter`、`--limit`、`--format` | 搜索 Docker Hub 公开镜像，仅用于初步发现。 |
| `image pull <image>` | `--platform`、`--quiet` | 拉取明确版本镜像；`--platform` 选择目标平台。 |
| `image ls` | `-a`、`--digests`、`--filter`、`--format` | 列出本地镜像；脚本应使用 `--format`。 |
| `image inspect` | `--format` | 查看镜像架构、入口命令、环境变量和 digest。 |
| `image history` | `--no-trunc`、`--format` | 查看镜像层，辅助分析体积。 |
| `image tag <source> <target>` | 无 | 新增 Tag，不复制镜像内容。 |
| `image save/load` | `-o`、`-i`、`-q` | 离线导出或导入镜像及其标签。 |

登录 Registry 时从标准输入读取密码或 Token，避免出现在 shell 历史和进程参数中：

```bash
printf '%s' '<token>' | docker login registry.example.com --username '<user>' --password-stdin
docker logout registry.example.com
```

```bash
docker image rm nginx:demo
docker image rm --force nginx:demo
docker image prune
docker image prune -a --filter 'until=168h'
```

`image prune` 删除悬空镜像；`image prune -a` 删除所有未被容器使用的镜像；`--filter until=<duration>` 可限制清理范围。`image rm --force` 和 `image prune -a` 执行前都应确认容器和回滚是否仍需要镜像。

## 镜像构建

镜像构建的 Dockerfile、构建上下文和 BuildKit 用法在[第 03 章镜像制作](../03-镜像制作/)展开；日常构建入口如下：

```bash
docker image build -t local/web:1.0.0 -f Dockerfile .
docker image build --pull --no-cache -t local/web:1.0.0 .
docker image build --target runtime -t local/web:debug .
```

| 参数 | 作用 |
| --- | --- |
| `-t <name:tag>`、`--tag` | 为构建结果指定镜像引用。 |
| `-f <file>`、`--file` | 指定 Dockerfile 路径；最后一个参数仍是构建上下文。 |
| `--build-arg KEY=VALUE` | 传递 Dockerfile 中的 `ARG`，不应用于密码或 Token。 |
| `--target <stage>` | 构建多阶段 Dockerfile 中的指定阶段。 |
| `--pull` | 构建前尝试拉取更新的基础镜像。 |
| `--no-cache` | 禁用构建缓存，适合验证缓存问题但会显著降低构建速度。 |
| `--platform <platform>` | 为支持多平台的构建器选择目标平台。 |

## 容器创建与运行

```bash
docker container run --rm -it nginx:1.31-alpine sh
docker container run -d --name web -p 8080:80 nginx:1.31-alpine
docker container create --name web-created nginx:1.31-alpine
docker container start web-created
docker container start -ai web-created
```

`container run` 会创建并启动新容器；`container create` 只创建不启动；`container start` 用于再次启动已有容器。

| `run` 参数 | 说明 |
| --- | --- |
| `-d`、`--detach` | 后台运行并输出容器 ID。 |
| `-i`、`--interactive` 与 `-t`、`--tty` | 保持标准输入、分配伪终端，常组合为 `-it`。 |
| `--rm` | 容器退出后自动删除容器和关联匿名卷，适合临时任务。 |
| `--name <name>` | 指定稳定名称，便于后续日志与排障。 |
| `--pull missing` | 缺少镜像时拉取；可选值还有 `always` 和 `never`。 |
| `-p [ip:]hostPort:containerPort` | 发布端口；仅本机访问时使用 `127.0.0.1:hostPort:containerPort`。 |
| `-P`、`--publish-all` | 将所有 `EXPOSE` 端口随机发布。 |
| `-e KEY=VALUE`、`--env-file <file>` | 设置环境变量或从文件读取；敏感值不应直接写入命令行。 |
| `-v source:target[:ro]` | 简写挂载方式，可用于 bind mount 或 volume。 |
| `--mount type=...,src=...,dst=...` | 字段化挂载方式，复杂挂载优先使用。 |
| `--network <network>` | 接入指定网络。 |
| `--restart <policy>` | `no`、`on-failure[:max-retries]`、`always`、`unless-stopped`。 |
| `--memory <limit>`、`--cpus <count>`、`--pids-limit <count>` | 分别限制内存、CPU 与进程数。 |
| `--user <uid[:gid]>`、`--read-only` | 指定运行用户、使根文件系统只读。 |
| `--entrypoint <cmd>`、`-w <dir>` | 覆盖入口命令、设置工作目录。 |
| `--health-cmd <cmd>`、`--health-interval <duration>`、`--health-retries <n>` | 设置健康检查及其周期、失败阈值。 |
| `--log-driver <driver>`、`--log-opt key=value` | 覆盖 Daemon 默认日志驱动或日志参数。 |

> [!IMPORTANT]
> `--rm` 与 `--restart` 不能同时使用。`--privileged`、`--pid host`、`--network host`、`--security-opt` 与挂载 Docker Socket 会扩大容器权限，不是普通服务的默认参数。

## 容器查看、排障与生命周期

```bash
docker container ls
docker container ls -a --filter status=exited
docker container ls --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
docker container inspect web --format '{{.State.ExitCode}} {{.State.OOMKilled}}'
docker container logs --tail 100 --since 10m --timestamps web
docker container logs -f web
docker container exec -it web sh
docker container cp web:/var/log/nginx/access.log ./access.log
docker container stats --no-stream web
docker container top web
docker container port web
docker container rename web web-v2
docker container pause web-v2
docker container unpause web-v2
docker container wait web-v2
```

| 命令 | 常用参数 | 作用 |
| --- | --- | --- |
| `container ls` | `-a`、`-q`、`--filter`、`--format` | 查看容器；`-a` 包含已退出容器。 |
| `container inspect` | `--format`、`--size` | 查看状态、退出码、OOM、挂载、网络和端口绑定。 |
| `container logs` | `-f`、`--tail`、`--since`、`--until`、`--timestamps` | 读取标准输出和标准错误。 |
| `container exec` | `-i`、`-t`、`-e`、`-u`、`-w`、`-d` | 在运行中的容器执行命令，不会改变主进程。 |
| `container cp` | `-a`、`-L` | 在容器与宿主机之间复制文件，仅用于临时操作或取证。 |
| `container stats` | `--no-stream`、`--format` | 查看实时或单次资源使用。 |
| `container top` | `-eo <fields>` | 查看容器内进程。 |
| `container port` | 无 | 查看端口发布结果。 |
| `container rename` | 无 | 修改容器名称，不重建容器。 |
| `container pause/unpause` | 无 | 暂停或恢复容器中的进程，不能替代正常停止服务。 |
| `container wait` | `--condition` | 等待容器达到 `not-running`、`next-exit` 或 `removed` 状态，并输出退出码。 |

```bash
docker container update --memory 512m --cpus 1 web
docker container restart --time 30 web
docker container stop --time 30 web
docker container kill --signal SIGTERM web
docker container rm web
docker container rm --force --volumes web
docker container prune --filter 'until=168h'
```

| 命令或参数 | 作用 |
| --- | --- |
| `container update` | 更新部分资源限制和重启策略，无法替代需要重建的配置变更。 |
| `restart/stop --time <seconds>` | 重启或停止前给进程优雅退出的等待时间。 |
| `kill --signal <signal>` | 直接发送指定信号，默认 `SIGKILL`。 |
| `rm --force` | 强制停止并删除容器。 |
| `rm --volumes` | 删除关联匿名卷，不删除 named volume。 |
| `container prune --filter` | 删除已停止容器，并按条件限制范围。 |

## 数据卷与挂载

```bash
docker volume create nginx-data
docker volume create --driver local --label app=demo nginx-data
docker volume ls --filter dangling=true
docker volume inspect nginx-data
docker volume rm nginx-data
docker volume prune
docker volume prune -a --filter 'label!=keep=true'
```

| 命令 | 常用参数 | 作用 |
| --- | --- | --- |
| `volume create` | `--driver`、`--label`、`--opt` | 创建 named volume；本地驱动是默认值。 |
| `volume ls` | `--filter`、`--format` | 列出 volume；`dangling=true` 查找未使用匿名卷。 |
| `volume inspect` | `--format` | 查看驱动、挂载点和标签。 |
| `volume rm` | `--force` | 删除指定 volume；使用中的 volume 默认不能删除。 |
| `volume prune` | `-a`、`--filter`、`-f` | 默认清理未使用匿名卷；`-a` 还会清理未使用 named volume。 |

> [!CAUTION]
> `volume prune -a` 和 `docker compose down -v` 可能删除业务数据。执行前必须确认卷引用、备份文件和恢复步骤。

## 容器网络

```bash
docker network ls
docker network create app-net
docker network create --driver bridge --subnet 172.30.0.0/24 --gateway 172.30.0.1 app-net
docker network inspect app-net
docker network connect --alias web-api app-net web
docker network disconnect app-net web
docker network rm app-net
docker network prune --filter 'until=168h'
```

| 命令或参数 | 作用 |
| --- | --- |
| `network create` | 创建网络，默认驱动为 `bridge`。 |
| `--driver` | 指定网络驱动；单机服务通常使用自定义 `bridge`。 |
| `--subnet`、`--gateway` | 明确 IPAM 网段和网关，避免与现有网络冲突。 |
| `--internal` | 创建外部隔离网络，仍应按应用连通性验证。 |
| `network inspect` | 查看网络配置、成员和 IP 地址。 |
| `network connect --alias` | 把运行中容器接入网络，并添加网络内 DNS 别名。 |
| `network disconnect` | 将容器移出网络。 |
| `network rm/prune` | 删除指定或未使用网络；先确认没有服务依赖。 |

自定义 bridge 网络内，容器可按名称和网络别名互访；`-p` 只用于发布给宿主机或外部网络。详见[容器网络](./4-容器网络.md)。

## Compose 服务组

```bash
docker compose version
docker compose -f compose.yaml -p demo config
docker compose --env-file .env up -d --build --remove-orphans
docker compose ps
docker compose logs -f --tail 100 web
docker compose exec web sh
docker compose run --rm --no-deps web env
docker compose pull
docker compose build --pull
docker compose down --remove-orphans
```

| 命令或参数 | 作用 |
| --- | --- |
| `-f <file>` | 指定 Compose 文件；多次使用可按顺序合并。 |
| `-p <project>`、`--project-name` | 覆盖项目名，避免多套环境资源名称冲突。 |
| `--env-file <file>` | 指定用于插值的环境变量文件。 |
| `compose config` | 校验并输出解析、插值和合并后的最终模型。 |
| `compose up -d` | 创建或更新服务并在后台运行。 |
| `up --build`、`up --pull` | 构建服务镜像、拉取镜像；`--pull` 可指定拉取策略。 |
| `up --force-recreate`、`--remove-orphans` | 强制重建容器、删除同项目中未定义的容器。 |
| `compose ps` | 查看服务容器、状态和端口。 |
| `compose logs -f --tail <n>` | 跟随服务日志并限制初始输出行数。 |
| `compose exec <service> <cmd>` | 在运行中服务容器执行命令。 |
| `compose run --rm --no-deps <service> <cmd>` | 创建一次性容器执行命令，退出后删除且不启动依赖。 |
| `compose pull/build --pull` | 拉取 service 镜像、构建时刷新基础镜像。 |
| `compose down` | 停止并删除项目容器和网络，默认保留 named volume。 |
| `down -v`、`--volumes` | 同时删除命名卷和匿名卷。 |
| `down --rmi local` | 删除仅由该 Compose 项目使用的镜像。 |

详见[Compose 服务编排](./5-Compose服务编排.md)。

## 清理前检查

```bash
docker system df -v
docker container ls -a
docker image ls
docker volume ls
docker network ls
docker builder prune --filter 'until=168h'
docker system prune --all --volumes --filter 'until=168h'
```

| 命令 | 删除范围 |
| --- | --- |
| `docker container prune` | 所有停止容器。 |
| `docker image prune` | 悬空镜像。 |
| `docker image prune -a` | 所有未被容器使用的镜像。 |
| `docker volume prune` | 未使用匿名卷。 |
| `docker volume prune -a` | 未使用匿名卷和 named volume。 |
| `docker network prune` | 未被容器使用的网络。 |
| `docker builder prune` | 未使用的构建缓存；`-a` 会清理所有未使用缓存。 |
| `docker system prune` | 停止容器、未使用网络、悬空镜像和构建缓存。 |
| `docker system prune -a` | 上述资源及所有未被容器使用的镜像。 |
| `docker system prune --volumes` | 在 `system prune` 中额外清理未使用的匿名卷。 |

> [!WARNING]
> 清理命令不会判断资源是否属于业务数据或发布回滚所需镜像。生产环境执行前应先看 `docker system df -v`，使用 `--filter` 缩小范围，并验证备份恢复结果。

## 常见排查

| 现象 | 优先检查 |
| --- | --- |
| 容器创建后立即退出 | `docker container ls -a`、`docker container logs <name>`、`docker container inspect <name>`。 |
| 端口发布失败 | `docker container port <name>` 和 `sudo ss -lntup`。 |
| 服务间名称无法解析 | `docker network inspect <network>`，确认容器在同一自定义 bridge 网络。 |
| bind mount 内容异常 | 宿主机路径、容器目标路径、文件权限和 Docker Desktop 共享目录。 |
| 卷数据丢失 | 是否执行 `volume rm`、`volume prune -a` 或 `compose down -v`，再从备份恢复。 |
| Compose 配置与预期不符 | `docker compose config` 检查多文件合并与变量插值。 |

## 参考

- [Docker CLI 参考](https://docs.docker.com/reference/cli/docker/)
- [docker container CLI 参考](https://docs.docker.com/reference/cli/docker/container/)
- [docker container run 命令](https://docs.docker.com/reference/cli/docker/container/run/)
- [docker image CLI 参考](https://docs.docker.com/reference/cli/docker/image/)
- [docker volume CLI 参考](https://docs.docker.com/reference/cli/docker/volume/)
- [docker network CLI 参考](https://docs.docker.com/reference/cli/docker/network/)
- [docker system prune 命令](https://docs.docker.com/reference/cli/docker/system/prune/)
- [docker compose CLI 参考](https://docs.docker.com/reference/cli/docker/compose/)
- [Docker Engine 29.6.1 发布说明](https://docs.docker.com/engine/release-notes/29/#2961)
- [Docker Compose v5.3.1 发布说明](https://github.com/docker/compose/releases/tag/v5.3.1)
