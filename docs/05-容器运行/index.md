# 容器运行

本章聚焦 Kubernetes 节点上的容器运行时体系，重点学习 CRI、containerd、ctr、crictl 和 nerdctl。前面已经学过 Docker、镜像制作和镜像仓库，本章要把视角切到 Kubernetes 节点内部：Pod 为什么不是用 `docker ps` 排查，镜像为什么要导入到 `k8s.io` 命名空间，私有仓库为什么 Docker 能拉但 kubelet 仍可能失败。

## 学习目标

- 理解 CRI 解决的问题，以及 kubelet 与容器运行时的通信关系。
- 说清 Docker、containerd、runc、CRI、OCI 之间的边界。
- 掌握 `ctr`、`crictl`、`nerdctl` 三类工具的适用场景。
- 能配置 containerd 访问 HTTP 或自签证书镜像仓库。
- 能在 Kubernetes 节点上排查镜像拉取、容器启动和运行时异常。

## 前置知识

学习本章前，建议已经掌握：

| 前置内容 | 对应章节 |
| --- | --- |
| 镜像、容器、仓库基本概念 | [容器基础](../02-容器基础/) |
| Dockerfile 与业务镜像制作 | [镜像制作](../03-镜像制作/) |
| Harbor 推送、拉取和权限 | [镜像仓库](../04-镜像仓库/) |
| kubeadm 集群初始化和 containerd 安装 | [入门起步](../01-入门起步/) |

## 目录

| 课时 | 内容 |
| --- | --- |
| [CRI 与 Containerd](./1-CRI与Containerd) | CRI 的定位、dockershim 移除、containerd 架构和状态检查 |
| [客户端工具与命名空间](./2-客户端工具与命名空间) | `ctr`、`crictl`、`nerdctl` 的职责差异，以及 `k8s.io` namespace |
| [镜像仓库配置](./3-镜像仓库配置) | HTTP/self-signed Harbor、containerd 1.x/2.x `hosts.toml` 和认证配置 |
| [镜像容器管理](./4-镜像容器管理) | 镜像拉取、导入导出、打标签、推送、container/task 排查 |
| [排障总结与面试](./5-排障总结与面试) | 常见故障路径、生产建议和面试问答 |
