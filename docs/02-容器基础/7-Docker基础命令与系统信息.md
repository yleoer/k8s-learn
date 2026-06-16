# Docker 基础命令与系统信息

安装 Docker 后，先用 `docker version` 和 `docker info` 确认客户端、服务端、运行时和系统配置。

## 查看版本

```bash
docker version
```

<details>
<summary>docker version 示例</summary>

```text
Client: Docker Engine - Community
 Version:           28.0.0
 API version:       1.48
 Go version:        go1.23.6
 OS/Arch:           linux/amd64

Server: Docker Engine - Community
 Engine:
  Version:          28.0.0
  API version:      1.48 (minimum version 1.24)
  Go version:       go1.23.6
  OS/Arch:          linux/amd64
  containerd:
   Version:          v2.2.4
  runc:
   Version:          1.3.0
```

</details>

重点关注：

- Client Version：客户端版本
- Server Version：Docker Engine 服务端版本
- containerd：底层 containerd 版本
- runc：底层 OCI runtime 版本
- OS/Arch：系统和 CPU 架构

## 查看详细信息

```bash
docker info
```

<details>
<summary>docker info 示例（关键字段）</summary>

```text
Client: Docker Engine - Community
 Server Version: 28.0.0
 Storage Driver: overlay2
 Cgroup Driver: systemd
 Cgroup Version: 2
 Logging Driver: json-file
 Docker Root Dir: /var/lib/docker
 Registry Mirrors:
  https://docker.1ms.run/
```

</details>

重点关注：

- Containers：容器数量
- Images：镜像数量
- Storage Driver：存储驱动
- Logging Driver：日志驱动
- Cgroup Driver：建议使用 `systemd`
- Docker Root Dir：Docker 数据目录，默认 `/var/lib/docker`
- Registry Mirrors：镜像加速地址

## 常用状态检查

```bash
systemctl status docker --no-pager
docker info
docker version
docker ps
docker images
```

如果 Docker 命令无法连接 daemon，优先检查：

```bash
sudo systemctl status docker --no-pager
sudo journalctl -u docker -xe --no-pager
```

普通用户执行 Docker 命令如果提示权限不足，可以加入 `docker` 组：

```bash
sudo usermod -aG docker "$USER"
newgrp docker
```

加入 `docker` 组等价于给用户较高的主机控制权限，生产环境要谨慎授权。
