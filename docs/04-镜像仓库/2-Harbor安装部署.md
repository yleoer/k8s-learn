# Harbor 安装部署

Harbor 是企业中常用的私有镜像仓库，适合部署在内网，用于统一管理业务镜像、基础镜像和 Helm Chart 等制品。

官网：<https://goharbor.io>

## 环境准备

- Linux 服务器（建议 4 核 / 8 GiB 内存 / 100 GiB 以上磁盘）。
- Docker 和 Docker Compose 已安装。
- 服务器主机名和 IP 稳定。
- 内网 DNS 或 `/etc/hosts` 已配置 Harbor 地址解析。

## 下载安装包

从 [Harbor Releases](https://github.com/goharbor/harbor/releases) 下载离线安装包：

```bash
wget https://github.com/goharbor/harbor/releases/download/v2.14.0/harbor-offline-installer-v2.14.0.tgz
```

离线包包含运行所需的全部镜像，适合内网环境。

## 解压并导入镜像

```bash
tar xf harbor-offline-installer-v2.14.0.tgz
cd harbor
docker load -i harbor.v2.14.0.tar.gz
```

## 修改配置文件

```bash
cp harbor.yml.tmpl harbor.yml
vim harbor.yml
```

重点字段：

```yaml
hostname: harbor.example.com

harbor_admin_password: Harbor12345

data_volume: /data/harbor
```

| 字段 | 说明 |
| --- | --- |
| `hostname` | Harbor 访问地址，域名或 IP |
| `harbor_admin_password` | 管理员 `admin` 的密码，安装前修改 |
| `data_volume` | 数据存储目录 |
| `http.port` | HTTP 端口，默认 80 |
| `https` | HTTPS 证书配置，生产环境建议配置 |

如果不配置 HTTPS，需要注释掉 `https` 相关段落，只保留 HTTP。

## HTTPS 证书（简要）

生产环境建议使用权威 CA 证书或 Let's Encrypt：

```yaml
https:
  port: 443
  certificate: /etc/harbor/certs/harbor.example.com.crt
  private_key: /etc/harbor/certs/harbor.example.com.key
```

测试环境可用自签证书，但客户端不能只靠“忽略错误”长期运行。推荐做法是：

| 场景 | 推荐方式 |
| --- | --- |
| 生产环境 | 使用企业 CA、权威 CA 或 Let's Encrypt 证书 |
| 内网自签 HTTPS | 将自签 CA 证书导入 Docker、containerd 和操作系统信任链 |
| 临时 HTTP 测试 | 明确配置 insecure registry，仅用于实验或封闭环境 |

如果 Harbor 使用 HTTPS 自签证书，建议把 CA 证书分发到所有需要拉取镜像的节点。Docker 客户端可放到：

```bash
sudo mkdir -p /etc/docker/certs.d/harbor.example.com
sudo cp ca.crt /etc/docker/certs.d/harbor.example.com/ca.crt
sudo systemctl restart docker
```

containerd 客户端可放到：

```bash
sudo mkdir -p /etc/containerd/certs.d/harbor.example.com
sudo cp ca.crt /etc/containerd/certs.d/harbor.example.com/ca.crt
sudo systemctl restart containerd
```

只有在 Harbor 明确使用 HTTP，或临时测试自签证书且无法下发 CA 时，才使用后续章节的 insecure 配置。

## 安装并启动

```bash
mkdir -p /data/harbor
./prepare
./install.sh
```

安装完成后，Harbor 通过 Docker Compose 启动以下组件：

| 组件 | 作用 |
| --- | --- |
| `nginx` | 反向代理，Harbor 入口 |
| `harbor-core` | 核心 API |
| `harbor-db` | PostgreSQL 数据库 |
| `harbor-jobservice` | 异步任务（复制、 GC） |
| `harbor-portal` | Web 控制台 |
| `registry` | 镜像分发服务 |
| `redis` | 缓存和会话 |
| `trivy-adapter` | 镜像漏洞扫描（可选） |

## 查看运行状态

```bash
docker compose ps
```

<details>
<summary>示例输出</summary>

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

## 登录 Web 控制台

浏览器访问 `http://harbor.example.com`，默认账号：

```text
admin / Harbor12345
```

如果安装前修改了 `harbor_admin_password`，以修改后的密码为准。

## 启停与卸载

```bash
docker compose stop      # 停止
docker compose up -d     # 启动
docker compose down -v   # 卸载（删除容器和卷）
```

::: danger 卸载风险
`docker compose down -v` 会删除 Compose 管理的卷。执行前至少确认已经备份 `harbor.yml`、数据库和 `/data/harbor`。生产环境不要把它当作普通重启命令使用。
:::
