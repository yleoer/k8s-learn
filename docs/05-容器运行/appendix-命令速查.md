# 容器运行速查

本章记录 CRI、containerd 及其客户端工具的观察和排障命令。`crictl` 面向 CRI，`ctr` 面向 containerd API，`nerdctl` 提供接近 Docker 的体验；三者不能混为同一抽象层。

## 关键对象与边界

| 对象 | 作用 | 不负责 |
| --- | --- | --- |
| CRI | kubelet 与运行时之间的接口 | 镜像仓库权限策略 |
| containerd namespace | 隔离 containerd 资源视图 | Kubernetes Namespace |
| crictl | 观察 CRI Pod sandbox 与容器 | 管理 Docker 容器 |

## 命令速查

### CRI 资源与日志

```bash
crictl ps -a
crictl pods
crictl images
crictl inspect <container-id>
crictl logs <container-id>
crictl info
```

### containerd 与镜像

```bash
ctr namespaces list
ctr -n k8s.io containers list
ctr -n k8s.io images list
nerdctl -n k8s.io ps -a
nerdctl -n k8s.io images
```

### 运行时状态

```bash
systemctl status containerd
journalctl -u containerd -n 100 --no-pager
```

## 配置速查

| 配置 | 检查重点 |
| --- | --- |
| `/etc/crictl.yaml` | runtime endpoint 与 image endpoint |
| containerd registry 配置 | 主机、TLS、凭据与镜像路径 |
| `k8s.io` namespace | Kubernetes 资源在 containerd 中的默认视图 |

## 排查索引

| 现象 | 优先检查 | 正文 |
| --- | --- | --- |
| kubelet 无法创建 sandbox | containerd 服务、CRI endpoint、日志 | [CRI 与 Containerd](./1-CRI与Containerd.md) |
| 镜像拉取失败 | registry 配置、证书和认证 | [镜像仓库配置](./3-镜像仓库配置.md) |
| Pod 与运行时视图不一致 | CRI 与 containerd namespace | [客户端工具与命名空间](./2-客户端工具与命名空间.md) |

## 关联页面

- [镜像容器管理](./4-镜像容器管理.md)
- [排障记录](./5-排障记录.md)

## 参考

- [容器运行时接口](https://kubernetes.io/docs/concepts/architecture/cri/)
