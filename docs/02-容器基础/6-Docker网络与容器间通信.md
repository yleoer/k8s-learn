# Docker 网络与容器间通信

前文的容器都通过 `-p` 端口映射对外提供服务，容器之间如何互访还没有展开。Docker 通过网络驱动为容器提供不同的网络形态，理解 bridge、host、none 三种单机驱动和容器间通信规则，是排查“容器连不上”问题和后续理解 Pod 网络的基础。

## 网络驱动总览

Docker 内置多种网络驱动，创建网络时通过 `-d` 指定：

| 驱动                   | 定位     | 说明                             |
|----------------------|--------|--------------------------------|
| `bridge`             | 默认驱动   | 宿主机内虚拟网桥，容器经 NAT 访问外部          |
| `host`               | 移除网络隔离 | 容器直接使用宿主机网络命名空间                |
| `none`               | 完全隔离   | 容器只有 loopback，无外部连通性           |
| `overlay`            | 跨主机    | 连接多个 Docker daemon，面向 Swarm 集群 |
| `ipvlan` / `macvlan` | 接入物理网络 | 容器以 VLAN 成员或独立 MAC 出现在外部网络     |

单机学习场景重点是前三种。查看当前网络：

```bash
docker network ls
```

::: details 输出类似如下

```text
NETWORK ID     NAME      DRIVER    SCOPE
96935c98f21a   bridge    bridge    local
44e231265795   host      host      local
3f2987d9cbdf   none      null      local
```

:::

`bridge`、`host`、`none` 三个网络随 Docker 启动自动创建，分别对应同名驱动。

## 默认 bridge 与自定义 bridge

未指定 `--network` 的容器接入默认 `bridge` 网络，对应宿主机上的 `docker0` 网桥。默认 bridge 有一个关键限制：容器之间只能通过 IP 互访，容器名不会被解析（`--link` 可以建立名称关联，但官方已将其标记为遗留能力）。

自定义 bridge 网络提供内置 DNS，容器名和网络别名可以直接解析，这也是官方明确推荐的方式：

```bash
docker network create app-net
docker run -d --name web --network app-net nginx:1.27-alpine
docker run --rm --network app-net busybox:1.36.1 wget -qO- http://web
```

第三条命令中的 `busybox` 容器通过容器名 `web` 直接访问 nginx，预期输出 nginx 欢迎页 HTML。对比默认 bridge 的行为：

```bash
docker run -d --name web-default nginx:1.27-alpine
docker run --rm busybox:1.36.1 wget -qO- --timeout=3 http://web-default
```

第二条命令预期解析失败报错，因为默认 bridge 没有容器名解析。

两种 bridge 的差异汇总：

| 对比项    | 默认 bridge             | 自定义 bridge                         |
|--------|-----------------------|------------------------------------|
| 容器名解析  | 不支持，仅 IP 或遗留 `--link` | 内置 DNS 按容器名、别名解析                   |
| 隔离边界   | 所有未指定网络的容器互通          | 只有加入同一网络的容器互通                      |
| 动态加入退出 | 需要重建容器                | `docker network connect` 可对运行中容器操作 |
| 网络配置   | 全局一份                  | 每个网络可独立配置                          |

自定义网络的内置 DNS 监听在容器内的 `127.0.0.11`；默认 bridge 的容器只是复制宿主机的 `/etc/resolv.conf`。同一自定义网络内的容器可以直接访问对方监听的端口，`-p` 只用于把容器端口发布到宿主机或其他网络访问入口。

## host 网络

`--network host` 让容器直接使用宿主机网络命名空间：容器没有独立 IP，应用监听的端口就是宿主机端口。

```bash
docker run --rm -d --network host --name web-host nginx:1.27-alpine
curl http://127.0.0.1:80
```

host 网络下 `-p`、`-P` 端口映射参数被忽略，Docker 会输出警告。它的价值在于性能和端口规模：没有 NAT 转换，也不需要为每个端口创建代理进程，适合高吞吐或需要监听大量端口的场景。代价是失去网络隔离：容器与宿主机、以及其他 host 网络容器共享端口空间，端口冲突时启动失败。

host 网络驱动原生只在 Linux 上可用；Docker Desktop 4.34 及以上版本可以在设置中启用 host networking 支持，但仅支持四层 TCP/UDP 转发。

## none 网络

`--network none` 完全隔离容器网络栈，容器内只有 loopback 设备：

```bash
docker run --rm --network none busybox:1.36.1 ip addr
```

预期只输出 `lo` 一个网络设备。none 网络适合完全不需要网络的任务，例如本地文件批处理、离线数据转换，或将网络交给其他工具单独配置的场景。

## 容器间通信要点

跨网络的容器默认不通。一个容器可以同时连接多个网络，运行中的容器也可以动态加入：

```bash
docker network create net-a
docker network create net-b
docker run -d --name multi --network net-a nginx:1.27-alpine
docker network connect net-b multi
docker inspect multi --format '{{json .NetworkSettings.Networks}}'
```

`--network-alias` 为容器在某个网络中添加额外 DNS 名称。多个容器可以共享同一别名，调用方访问这个别名时会解析到多个后端容器地址。下面用两个 nginx 容器分别返回不同内容，观察别名解析和访问结果。

```bash
docker network create alias-net

docker run -d --name web-a \
> --network alias-net \
> --network-alias web-pool \
> nginx:1.27-alpine \
> sh -c 'printf "web-a\n" > /usr/share/nginx/html/index.html && nginx -g "daemon off;"'

docker run -d --name web-b \
> --network alias-net \
> --network-alias web-pool \
> nginx:1.27-alpine \
> sh -c 'printf "web-b\n" > /usr/share/nginx/html/index.html && nginx -g "daemon off;"'
```

查看两个后端容器在该网络中的地址和别名：

```bash
docker inspect web-a web-b --format '{{.Name}} {{range $network, $conf := .NetworkSettings.Networks}}network={{$network}} ip={{$conf.IPAddress}} aliases={{json $conf.Aliases}}{{end}}'
```

::: details 输出类似如下

```text
/web-a network=alias-net ip=172.21.0.2 aliases=["web-pool"]
/web-b network=alias-net ip=172.21.0.3 aliases=["web-pool"]
```

:::

通过别名访问服务：

```bash
docker run --rm --network alias-net busybox:1.36.1 sh -c 'for i in 1 2 3 4; do wget -qO- http://web-pool; done'
```

::: details 输出类似如下

```text
web-a
web-b
web-b
web-b
```

:::

实际返回顺序取决于 Docker DNS 返回的地址顺序和客户端解析行为，`--network-alias` 不做健康检查，也不提供 Kubernetes Service 那样的服务抽象。它适合本地验证或简单的名称兼容场景；需要稳定负载均衡时，应使用反向代理、Docker Compose 服务名或后续 Kubernetes Service。

清理示例资源：

```bash
docker rm -f web-a web-b
docker network rm alias-net
```

容器访问宿主机服务时，约定使用 `host.docker.internal` 主机名。Docker Desktop 自动解析该名称，Linux 上需要显式映射到宿主机网关：

```bash
docker run --rm --add-host host.docker.internal=host-gateway busybox:1.36.1 ping -c 1 host.docker.internal
```

## 常用命令

```bash
docker network ls                        # 列出网络
docker network create app-net           # 创建自定义 bridge 网络
docker network inspect app-net          # 查看网络详情与已连接容器
docker network connect app-net web      # 将运行中容器加入网络
docker network disconnect app-net web   # 将容器移出网络
docker network rm app-net               # 删除网络
docker network prune                    # 删除所有未被使用的网络
```

## 记录要点

- 服务间互访一律创建自定义 bridge 网络并使用容器名，不依赖默认 bridge 和容器 IP——容器重建后 IP 会变化。
- host 网络是性能与隔离的取舍，使用前确认端口占用和安全边界。
- 同一自定义网络内互访不需要 `-p`；只有需要从宿主机或外部网络访问容器端口时才需要发布端口。
- 排查连通性时按顺序确认：两个容器是否在同一网络、目标名称能否解析、目标端口是否在监听。
- Kubernetes 不使用 Docker 网络模型：Pod 网络由 CNI 插件提供，Pod 之间无 NAT 直通。此处的 bridge、DNS 概念有助于理解，但配置方式不可迁移。

## 参考

- [Docker networking overview](https://docs.docker.com/engine/network/)
- [Bridge network driver](https://docs.docker.com/engine/network/drivers/bridge/)
- [Host network driver](https://docs.docker.com/engine/network/drivers/host/)
- [None network driver](https://docs.docker.com/engine/network/drivers/none/)
- [docker network CLI](https://docs.docker.com/reference/cli/docker/network/)
- [docker run CLI](https://docs.docker.com/reference/cli/docker/container/run/)
