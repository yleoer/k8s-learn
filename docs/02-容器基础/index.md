# 容器基础

第 01 章已通过 kubeadm 与 containerd 完成了 Kubernetes 集群的搭建。Pod 内部的本质是容器，因此理解容器的运行原理与操作方式，是深入理解 Kubernetes 的必要前提。

本章从 Docker 命令行入手，依次覆盖容器运行模型、Docker 架构、镜像管理、容器排障、数据持久化、服务部署流程、容器网络和 Compose 多容器编排。这些记录为后续 Pod 调度、容器运行时、镜像拉取和应用部署提供直观基础。

## 参考

- [Docker Engine 文档](https://docs.docker.com/engine/)
- [Docker CLI 参考](https://docs.docker.com/reference/cli/docker/)
- [Docker 存储：volume 与 bind mount](https://docs.docker.com/engine/storage/)
- [Docker 网络](https://docs.docker.com/engine/network/)
- [Docker Compose](https://docs.docker.com/compose/)
- [containerd image store with Docker Engine](https://docs.docker.com/engine/storage/containerd/)
- [Migrating from dockershim](https://kubernetes.io/docs/tasks/administer-cluster/migrating-from-dockershim/)
