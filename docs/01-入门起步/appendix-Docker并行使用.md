# Docker 并行使用

Kubernetes v1.24 以后已经移除了内置 dockershim。本阶段集群运行时是 containerd，部署完成后仍然可以安装和使用 Docker Engine，但推荐把它作为独立构建或调试工具使用。

## 适用场景

- 节点已经通过 kubeadm 部署好 Kubernetes。
- Kubernetes 使用 containerd 作为 CRI runtime。
- 仍希望在节点上使用 `docker run`、`docker build`、`docker compose`。

确认 Kubernetes 当前正常：

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
sudo systemctl status containerd --no-pager
```

## 安装 Docker Engine

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin
```

配置 Docker daemon：

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

启动 Docker：

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

## Docker 和 Kubernetes 的镜像不共享

默认情况下，Docker 和 Kubernetes 即使都依赖 containerd，也不是同一个管理视图：

- `docker images` 看到的是 Docker 管理的镜像。
- `sudo crictl images` 看到的是 Kubernetes CRI runtime 里的镜像。
- `sudo ctr -n k8s.io images ls` 可以查看 Kubernetes namespace 下的 containerd 镜像。

如果本地用 Docker 构建镜像，并希望 Kubernetes 使用，推荐推送到镜像仓库：

```bash
docker build -t registry.example.com/demo/myapp:v1 .
docker push registry.example.com/demo/myapp:v1
kubectl set image deployment/myapp myapp=registry.example.com/demo/myapp:v1
```

单机实验也可以把 Docker 镜像导出，再导入到 containerd 的 `k8s.io` namespace：

```bash
docker save myapp:v1 -o myapp-v1.tar
sudo ctr -n k8s.io images import myapp-v1.tar
sudo crictl images | grep myapp
```

Kubernetes 使用本地导入镜像时，建议配置：

```yaml
imagePullPolicy: IfNotPresent
```
