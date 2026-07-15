# 容器基础

第 01 章记录了 kubeadm 与 containerd 集群的搭建。本章回到 Pod 所依赖的容器运行模型，以 Docker 作为本地构建、运行和排查容器的观察入口。

本章依次整理容器与运行时、镜像管理、单容器运行与数据管理、容器网络及 Compose 服务编排，并附带按对象检索的 Docker 命令速查。这些记录为后续理解 Pod、镜像拉取、存储挂载、服务发现和声明式应用配置提供对照。

> [!NOTE]
> 本章命令以 Docker Engine 29.6.1 与随发行版提供的 Docker CLI 为基线整理。
>
> Docker Desktop、rootless 模式和不同 Linux 发行版的软件包可能存在差异，应先执行 `docker version` 与 `docker info` 核对实际环境。

## 参考

- [Docker Engine 文档](https://docs.docker.com/engine/)
- [Docker CLI 参考](https://docs.docker.com/reference/cli/docker/)
- [Docker 存储：volume 与 bind mount](https://docs.docker.com/engine/storage/)
- [Docker 网络](https://docs.docker.com/engine/network/)
- [Docker Compose](https://docs.docker.com/compose/)
- [Docker Engine 29.6.1 release notes](https://docs.docker.com/engine/release-notes/29/#2961)
- [containerd image store with Docker Engine](https://docs.docker.com/engine/storage/containerd/)
- [Migrating from dockershim](https://kubernetes.io/docs/tasks/administer-cluster/migrating-from-dockershim/)
