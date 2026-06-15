认识 Containerd

## 什么是CRI

CRI（Container Runtime Interface）三Kubernetes中用于实现容器运行时和Kubernetes之间交互的标准化接口。CRI定义了Kubernetes与底层容器运行时的通信协议和接口规范，可以让Kubernetes与不同的容器运行时进行交互，实现跨容器运行时的一致性，以达到在不需要改动任何代码的情况下支持多种运行时，比如Containerd/CRI-0/Kata等

## 什么是 Containerd

Containerd是一种容器运行时，可以管理容器的整个生命周期，包含镜像的传输/容器的运行和销毁/容器的监控，同时也可以管理更底层的存储和网络等。

Containerd属于Docker引擎中的一部分，在2016年12月从Docker Engine中剥离，成为了一个可以独立使用的容器运行时（Runtime），并且在2017年捐赠给了CNCF，成为了CNCF 的顶级项目之一。

## Containerd 和 Docker 的关系

Docker 包含 Containerd，但 Containerd 并不完全依赖于 Docker。Docker 是一个完整的容器化平台，提供了镜像构建/容器管理/网络管理/存储管理等功能。而Containerd只是作为Docker的一个组件，负责容器的生命周期管理。

## Containerd 客户端工具

- ctr：Containerd 原生客户端工具
- nerdctr：用于 Containerd 并且友好兼容 Docker Cli 使用习惯
- crictl：为 k8s 设计，遵循 CRI 接口规范

## Containerd 配置 insecure registry

```bash
vim /etc/containerd/config.toml
[plugins."io.containerd.grpc.v1.cri".registry.mirrors]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."192.168.2.108"]
  endpoint = ["http://192.168.2.108"]

systemctl restart containerd
```

> 要修改所有节点的配置
>
> 有没有方法方便快捷修改所有节点的配置？
>
> config.toml 并不是给 ctr 使用的，所以 ctr 拉取镜像需要加 `--plain-http`，拉取似有仓库需要指定用户名 `--user admin`
>
> Docker 拉取的镜像和 containerd 的没有关系

## Containerd 2.x 配置 insecure registry

// TODO

## Containerd 的命名空间管理

Containerd 的 Namespace 是一个强大的工具，主要用于实现容器之间的资源隔离/访问控制和安全性。可以实现多个容器在同一台主机上独立运行而不会相互干扰，从而提高了系统的可拓展性和管理性。

> Containerd 的命名空间和 Kubernetes 的命名空间是两个不同的概念。

```bash
ctr ns -h
ctr ns ls [-q]
ctr ns c test
ctr ns label test a=b
ctr ns rm
```

> k8s 用的 namespace 是 k8s.io
>
> 所有节点都要导入镜像，策略需要改成 IfNotPresent

## Containerd 镜像管理

```bash
ctr -n k8s.io i ls
ctr i pull centos:7
ctr i rm
ctr i tag
ctr i push xxx --user --http-plain
ctr i export/import
ctr i mount/unmout
```

## Containerd 容器管理

```bash
ctr -n k8s.io c ls
ctr c create IMAGE NAME
ctr c info NAME
ctr c rm
```

## nerdctl 工具

在 https://github.com/containerd/nerdctr/release 下载安装包

```bash
tar xf nerdctr-x-linux-amd64.tar.gz
mv nerdctl /usr/local/bin/
```

```bash
nerdctr version
nerdctr -n k8s.io ps
```

// TODO 补充其他参数

// TODO crictl 工具补充

## 常见面试问题

### 为什么 k8s 不再支持 Docker，而是选择其他的运行时

k8s 为了兼容 Docker 单独维护了 dockershim，浪费了大量的时间和精力，后来引入 CRI 接偶了和容器运行时的强依赖

### k8s 不支持 Docker 以后，还能用 Docker 制作镜像吗

可以，任何符合 OCI 的镜像都可以在 k8s 中部署

### Docker 和 Containerd 之间的关系

Containerd 本身是属于 Docker 的一部分，后来从 Docker 中剥离

// TODO 其他面试问题

Docker 的概念和架构