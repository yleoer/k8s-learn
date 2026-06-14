# 03-4 Harbor 仓库下载与安装

Harbor 是企业中常用的私有镜像仓库，适合部署在内网，用于统一管理业务镜像、基础镜像和 Helm Chart 等制品。

官方网站：

```text
https://goharbor.io
```

## 下载安装包

下载 Harbor 离线安装包，例如：

```text
harbor-offline-installer-v2.14.14.tgz
```

离线包中包含 Harbor 运行所需的镜像，适合内网环境安装。

## 解压并导入镜像

```bash
tar xf harbor-offline-installer-v2.14.14.tgz
cd harbor
docker load -i harbor.v2.14.14.tar.gz
```

## 修改配置文件

Harbor 默认提供配置文件模板，需要复制后再修改：

```bash
cp harbor.yml.tmpl harbor.yml
vim harbor.yml
```

重点修改字段：

```yaml
hostname: YOUR_HARBOR_ADDRESS

harbor_admin_password: Harbor12345

data_volume: /data/harbor
```

字段说明：

- `hostname`：Harbor 的访问地址，可以是域名或 IP。
- `https`：生产环境建议配置权威证书。如果不使用 HTTPS，客户端需要额外配置 `insecure-registry`。
- `harbor_admin_password`：管理员密码，默认账号为 `admin`，密码建议安装前修改。
- `data_volume`：Harbor 数据目录，示例使用 `/data/harbor`。

如果暂时不配置 HTTPS，可以注释或移除 `https` 相关配置，只保留 HTTP 访问。

## 创建数据目录并安装

```bash
mkdir /data/harbor -p
./prepare
./install.sh
```

安装完成后，Harbor 会通过 Docker Compose 启动多个组件。

## 查看运行状态

```bash
docker ps
```

如果需要在 Harbor 目录中查看服务状态：

```bash
docker compose ps
```

## 登录 Web 控制台

浏览器访问：

```text
http://YOUR_HARBOR_ADDRESS
```

默认管理员账号：

```text
admin / Harbor12345
```

如果安装前修改了 `harbor_admin_password`，以修改后的密码为准。
