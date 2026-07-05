# Docker 并行使用

Kubernetes v1.24 起已移除内置的 dockershim，本阶段集群运行时统一使用 containerd。

即便如此，仍可以在节点上单独安装 Docker Engine，将其作为镜像构建或本地调试的独立工具使用，而不影响 Kubernetes 的正常运行。

## 适用场景

本文适用于以下情形：

- 节点已通过 kubeadm 完成 Kubernetes 部署，运行时为 containerd。
- 仍需在节点上使用 `docker run`、`docker build` 或 `docker compose` 等工具。

操作前，先确认 Kubernetes 集群处于正常状态：

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
sudo systemctl status containerd --no-pager
```

## 安装 Docker Engine

Docker APT 源已在本章 [运行时与组件安装](./2-运行时与组件安装.md) 中添加，直接安装所需组件即可：

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin
```

配置 Docker daemon，启用 systemd cgroup driver 并设置日志轮转与镜像加速：

```bash
sudo mkdir -p /etc/docker

sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.1panel.live",
    "https://docker.sparkcr.cn",
    "https://hub.rat.dev",
    "https://dockerproxy.net"
  ]
}
EOF
```

启动服务并验证安装结果：

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now docker
sudo systemctl restart docker
```

检查 Docker：

```bash
sudo docker version
sudo docker info
sudo docker run --rm hello-world
docker compose version
```

## 镜像命名空间隔离

Docker Engine 与 Kubernetes 使用不同的运行时入口和管理视图，镜像不会自动互通：

- `docker images` 查看 Docker 守护进程管理的镜像。
- `sudo crictl images` 查看 Kubernetes CRI 运行时中的镜像。
- `sudo ctr -n k8s.io images ls` 直接查看 containerd `k8s.io` 命名空间下的镜像。

**本地导入的镜像只存在于导入节点上的 containerd `k8s.io` 命名空间中**。Docker 的 `registry-mirrors` 配置只影响 Docker 守护进程的镜像拉取，不影响 containerd 的镜像拉取；反之，containerd 的 `hosts.toml` 加速配置也只影响 CRI 运行时，Docker 不会受益。需要在 containerd 中配置镜像加速时，参照本章 [运行时与组件安装](./2-运行时与组件安装.md) 中「可选：配置镜像加速」小节。

**推荐做法**：通过镜像仓库中转，使 Kubernetes 拉取 Docker 构建的镜像。已有 Deployment `myapp` 时，可更新其中名为 `myapp` 的容器镜像：

```bash
docker build -t registry.example.com/demo/myapp:v1 .
docker push registry.example.com/demo/myapp:v1
kubectl set image deployment/myapp myapp=registry.example.com/demo/myapp:v1
```

**单机实验**：也可以将 Docker 镜像导出后直接导入到 containerd 的 `k8s.io` 命名空间，无需推送到远端仓库：

```bash
docker save myapp:v1 -o myapp-v1.tar
sudo ctr -n k8s.io images import myapp-v1.tar
sudo crictl images | grep myapp
```

通过本地导入方式使用镜像时，将拉取策略设置为 `IfNotPresent`，避免 Kubernetes 尝试从远端仓库重新拉取。以下使用 Deployment 资源为例：

```yaml [deployment.yaml]
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-local
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
        - name: myapp
          image: myapp:v1
          imagePullPolicy: IfNotPresent
```

该方式只适合单节点或可控调度的实验场景。本地镜像必须存在于 Pod 实际调度到的节点上；多节点环境更建议通过镜像仓库分发。
