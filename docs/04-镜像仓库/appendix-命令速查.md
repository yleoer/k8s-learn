# 镜像仓库速查

本章围绕镜像仓库、Harbor 项目和凭据边界整理常用操作。仓库负责分发与权限控制，不替代镜像构建、漏洞修复或运行时准入。

## 关键对象与边界

| 对象 | 作用 | 不负责 |
| --- | --- | --- |
| Harbor 项目 | 隔离仓库、成员与策略 | 运行中的工作负载权限 |
| Robot Account | 为自动化提供可撤销凭据 | 代替 Kubernetes RBAC |
| 镜像 tag | 标识发布版本 | 保证镜像内容不可变 |

## 命令速查

### 登录、推送与拉取

```bash
docker login <registry.example.com>
docker tag nginx:1.31-alpine <registry.example.com>/<project>/nginx:1.31-alpine
docker push <registry.example.com>/<project>/nginx:1.31-alpine
docker pull <registry.example.com>/<project>/nginx:1.31-alpine
docker logout <registry.example.com>
```

### Harbor 服务观察

```bash
docker compose ps
docker compose logs --tail=100
docker compose down
```

`docker compose down` 仅适用于[Harbor 安装部署](./2-Harbor安装部署.md)中的本地 Compose 环境；删除持久卷或数据前需另行确认备份与恢复方案。

## 配置速查

| 配置 | 检查重点 |
| --- | --- |
| 项目可见性 | 私有项目需要认证；公开项目仍需审查拉取范围 |
| 保留策略 | 按不可变发布 tag 保留，不依赖 `latest` |
| 漏洞策略 | 扫描结果、允许清单和阻止拉取策略分别审查 |

## 排查索引

| 现象 | 优先检查 | 正文 |
| --- | --- | --- |
| 推送被拒绝 | 项目权限、Robot Account、镜像路径 | [权限管理](./4-Harbor权限管理.md) |
| 拉取失败 | 仓库证书、凭据、镜像 tag | [镜像管理](./3-Harbor镜像管理.md) |
| 服务不可用 | Compose 服务与 Harbor 日志 | [扩展运维](./7-Harbor扩展运维.md) |

## 关联页面

- [镜像仓库概述](./1-镜像仓库概述.md)
- [镜像供应链安全](./6-镜像供应链安全.md)
- [Harbor 漏洞扫描](./8-Harbor漏洞扫描.md)

## 参考

- [Harbor 文档](https://goharbor.io/docs/)
