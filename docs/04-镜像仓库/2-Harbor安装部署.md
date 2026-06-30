# Harbor 安装部署

Harbor 是 CNCF 托管的企业级开源镜像仓库，常用于内网镜像分发、权限隔离、漏洞扫描和跨站点复制。本章以 Harbor v2.14 离线安装包为例，在单台 Linux 服务器上完成 Docker Compose 部署。

## 运行环境

| 项目 | 最低配置 | 建议配置 |
| --- | --- | --- |
| CPU | 2 核 | 4 核及以上 |
| 内存 | 4 GiB | 8 GiB 及以上 |
| 磁盘 | 40 GiB | 160 GiB 及以上，数据目录独立挂载 |
| Docker Engine | 20.10 以上 | 使用发行版官方或 Docker 官方稳定版本 |
| Docker Compose | 2.3 以上 | 使用 `docker compose` 插件形式 |

服务器主机名和 IP 应保持稳定，内网 DNS 或 `/etc/hosts` 需要提前配置 Harbor 域名的正向解析。若使用 HTTPS，还需要准备与 `hostname` 匹配的证书和私钥。

## 下载安装包

从 [Harbor Releases](https://github.com/goharbor/harbor/releases) 获取离线安装包：

```bash
wget https://github.com/goharbor/harbor/releases/download/v2.14.0/harbor-offline-installer-v2.14.0.tgz
```

离线安装包包含 Harbor 运行所需的组件镜像，适合无法直接访问外网镜像仓库的内网环境。实际部署时可根据官方发布页选择同一大版本中的最新补丁版本。

## 解压并导入镜像

```bash
tar xf harbor-offline-installer-v2.14.0.tgz
cd harbor
docker load -i harbor.v2.14.0.tar.gz
```

`docker load` 会将 Harbor 各组件镜像加载到本地 Docker，后续安装脚本可直接使用本地镜像生成并启动服务。

## 修改配置文件

复制配置模板并编辑：

```bash
cp harbor.yml.tmpl harbor.yml
vim harbor.yml
```

HTTP 方式的 `harbor.yml` 示例：

```yaml
hostname: harbor.example.com
http:
  port: 80
harbor_admin_password: <harbor-admin-password>
database:
  password: <harbor-db-password>
data_volume: /data/harbor
trivy:
  ignore_unfixed: false
jobservice:
  max_job_workers: 10
```

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `hostname` | 是 | Harbor 对外访问地址，必须使用客户端可访问的域名或 IP，不应使用 `127.0.0.1` 或 `localhost` |
| `harbor_admin_password` | 是 | 管理员 `admin` 的初始密码，使用本地安全密码，安装完成后应立即修改 |
| `data_volume` | 是 | 镜像数据、数据库和任务数据的存储目录，建议使用独立磁盘 |
| `http.port` | 否 | HTTP 访问端口，默认 `80` |
| `https` | 否 | HTTPS 证书配置，生产环境建议启用 |

## HTTP 与 HTTPS

测试环境可以注释 `https` 段，只保留 HTTP 访问。此时所有需要访问 Harbor 的 Docker、containerd 或 Kubernetes 节点都必须配置对该仓库的非安全访问或信任规则。

生产环境应配置权威 CA 证书或内部统一签发的受信任证书。启用 HTTPS 时，`harbor.yml` 可按下面的结构保留 HTTP 监听并补充 HTTPS 证书路径：

```yaml
hostname: harbor.example.com
http:
  port: 80
https:
  port: 443
  certificate: /etc/ssl/certs/harbor.example.com.crt
  private_key: /etc/ssl/private/harbor.example.com.key
harbor_admin_password: <harbor-admin-password>
database:
  password: <harbor-db-password>
data_volume: /data/harbor
trivy:
  ignore_unfixed: false
jobservice:
  max_job_workers: 10
```

自签证书也可以使用，但每个客户端节点都需要额外导入 CA 或配置跳过校验。集群规模扩大后，统一证书信任链比逐台配置 `insecure-registry` 更易维护。

## 安装用户与目录权限

Harbor 官方离线安装流程通常以具备 Docker 权限的运维账号执行 `sudo ./install.sh`。不建议为规避权限问题修改官方 `prepare` 脚本，也不应将数据目录设置为全局可写。

安装前应提前创建数据目录，并将目录归属和权限调整为符合本机 Docker、备份和运维流程的最小权限。示例：

```bash
sudo mkdir -p /data/harbor
sudo chown root:root /data/harbor
sudo chmod 0750 /data/harbor
```

如果使用普通用户管理安装目录，需要确保该用户能读取 Harbor 安装包解压后的文件，并通过 `sudo` 调用安装脚本：

```bash
sudo ./prepare
sudo ./install.sh
```

## 安装并启动

```bash
mkdir -p /data/harbor

# 生成配置并检查语法
sudo ./prepare

# 安装并启动所有组件
sudo ./install.sh
```

<details>
<summary>./install.sh 输出末尾类似如下</summary>

```text
✔ ----Harbor has been installed and started successfully.----
```

</details>

安装失败时可优先检查以下项目：

- `docker compose` 命令是否存在，版本是否满足要求
- 80、443 等端口是否已被其他服务占用
- `/data/harbor` 所在分区是否具备足够空间
- `hostname` 是否能从客户端和服务器本机正确解析

端口占用可通过以下命令确认：

```bash
ss -lntp | grep -E ':80|:443'
```

## Harbor 组件一览

安装完成后，Harbor 通过 Docker Compose 管理以下主要容器：

| 组件 | 作用 |
| --- | --- |
| `nginx` | 反向代理，作为 Harbor 的统一入口 |
| `harbor-core` | 核心 API，处理 Web 请求、认证和项目逻辑 |
| `harbor-db` | PostgreSQL 数据库，存储项目、用户、策略和任务数据 |
| `harbor-jobservice` | 异步任务执行器，负责复制、垃圾回收、扫描等任务 |
| `harbor-portal` | Web 控制台前端 |
| `registry` | Registry 服务，负责镜像层和清单的存储与分发 |
| `registryctl` | Registry 控制组件，辅助配置和管理 Registry |
| `redis` | 会话缓存和任务队列 |
| `trivy-adapter` | 漏洞扫描适配器，启用 Trivy 时出现 |

## 查看运行状态

```bash
docker compose ps
```

<details>
<summary>docker compose ps 输出类似如下</summary>

```text
NAME                STATUS
harbor-core         running
harbor-db           running
harbor-jobservice   running
harbor-log          running
harbor-portal       running
nginx               running
redis               running
registry            running
registryctl         running
```

</details>

主要组件均为 `running` 时，表示服务已正常启动。若某个组件反复重启，可通过 `docker compose logs <service>` 查看对应日志。

## 登录 Web 控制台

浏览器访问 `http://harbor.example.com` 或实际配置的 HTTPS 地址，使用安装时配置的管理员账号登录：

```text
用户名：admin
密码：  <harbor-admin-password>
```

首次登录后应立即进入 **系统管理 → 用户管理** 修改 `admin` 密码，并根据业务边界创建项目和用户。

## 启停管理

```bash
docker compose stop          # 停止所有组件，保留数据和配置
docker compose up -d         # 重新启动
docker compose down          # 停止并删除容器，保留持久化数据
docker compose down -v       # 停止并删除容器和数据卷，谨慎使用
```

日常维护通常使用 `docker compose stop` 和 `docker compose up -d`。`docker compose down -v` 会删除 Compose 管理的数据卷，只应在明确需要彻底清理测试环境时使用。
