# 认识kubernetes

## Kubernetes 基本概念

Kubernetes（简称k8s，希腊语，意为舵手）是一个开源的容器编排系统，用于容器的自动化部署/扩展，以及提供高可用和负载均衡的运行环境。

Kubernetes 提供了一个便携/高效的PaaS平台，降低了在物理机或虚拟机上调度和运行服务的难度，同时Kubernetes还整合了网络/存储/安全/监控等能力，是一个非常完善的“云原生操作系统”

Kubernetes的前身三谷歌内部的Borg系统，是基于谷歌15年生产环境经验的基础上开源的一个项目。

## 为什么k8s是云原生的最佳选择

Docker

- 缺乏完整的生命周期管理
- 缺乏服务发现/负载均衡/配置管理/存储管理
- 程序的扩容/部署/回滚和更新依旧不够灵活
- 宿主机宕机容器无法自动恢复
- 程序级健康检查依旧不到位
- 端口管理比较复杂
- 流量管理依旧复杂

 Kubernetes 特点和能力

- 开源开放，弹性伸缩，服务发现，负载均衡
- 自愈能力，健康检查，滚动更新，一键回滚
- 高可用，声明式，多环境，隔离性

## k8s核心组件/核心资源及架构剖析

### Kubernetes 架构

- Kubectl
- 控制节点
  - 状态管理 ControllerManager
  - 调用中心 Scheduler
  - 控制中枢 APIServer
  - 数据存储 Etcd
- 工作节点
  - Addons(CoreDNS/Calico)
  - Kube-Proxy
  - Kubelet
  - Runtime

### Kubernetes 控制节点核心组件

APIServer 是整个集群的控制中枢，提供集群中各个模块之间的数据交换，并将集群状态和信息存储在分布式健-值（key-value）存储系统Etcd集群中。同时它也是集群管理/资源配额/提供完备的集群安全机制的入口，为集群各类资源对象提供增删改查以及watch的REST API接口。

Scheduler 三集群 Pod 的调度中心，主要三通过调度算法将 Pod 分配到最佳的 Node 节点，它通过 APIServer 监听所有 Pod 的状态，一旦发现新的未被调度到任何Node节点的Pod，就会根据一系列策略选择最佳节点来进行调度，对每一个Pod创建一个绑定（binding），然后被调度的节点上的Kubelet负责启动该Pod。

Controller Manager 是集群状态管理器，以保证Pod或其他资源达到期望值。比如集群中某个服务的副本数或其他资源因故障和错误导致无法正常运行，没有达到设定的值时，Controller Manager 会尝试自动修复并使其达到期望状态。

Etcd用作 Kubernetes 的后台数据库，用于存储 Kubernetes 集群中的数据。Etcd由CoreOS开发，是一种持久性/轻量型/分布式的健-值（key-value）数据存储组件。

### Kubernetes 工作节点核心组件

Kubelet 负责管理该节点上的 Pod，同时对容器进行健康检查及监控，并且负责上报节点和节点上面Pod的状态

Kube-Proxy 负责维护节点上的网络规则，允许从集群内部或外部的网络与Pod进行网络通信。同时负责维护Service和Pod之间的请求路由和流量转发

Container Runtime 符合 CRI 接口规范的容器运行时，负责管理 Kubernetes 环境中容器的生命周期

CoreDNS 用于 Kubernetes 集群内部 Service 的解析，和上游域名的解析转发。可以让Pod把Service名称解析成Service的IP，然后通过Service的IP地址进行连接到对应的应用上，同时对外部的域名将会转发到外部的DNS进行解析

Calico 符合 CNI 标准的一个网络插件，它负责给每个Pod分配一个不会重复的IP，并且把每个节点当作一个“路由器”，这样一个节点的Pod就可以通过Pod的IP地址访问到其他节点的Pod

Metrics Server 一个用于Kubernetes集群的监控工具，它负责收集/存储和提供关于集群中各种资源的度量数据，比如CPU和内存。同时为Horizontal Pod Autoscaler（HPA）和 Vertical Pod Autoscaler（VPA）提供所需的资源指标数据。

###  Kubernetes 组件细节

APIServer 无状态组件，是唯一一个直接和 Etcd 通信的组件，可以直接进行横向扩容

Scheduler和Controller 有状态组件，主节点信息保存在leases资源中，可以通过 kubectl get leases -n kube-system 获取，也可以进行横向扩容，选主过程无需人工干预

Kube-Proxy 可选组件，如果使用 Cilium 作为 CNI组件，可以不安装 Proxy

Etcd 生产环境中建议部署为大于3的奇数个数的Etcd节点，以保证数据的安全性和可恢复性，并且Etcd的数据盘需要使用SSD硬盘

Kubectl 集群的管理工具，只要有Kubeconfig和Kubectl文件，就可以在任意地方对集群进行管理操作

### Kubernetes 交互链路

//TODO 图+链路说明

## Kubernetes常用核心资源分类

最小单元：Pod, Container

调度资源：Deployment, StatefulSet, DaemonSet, ReplicaSet, Replicatioin Controller

任务管理：CronJob, Job

服务发现：Endpoints, Service, Ingress

配置管理：ConfigMap, Secret

存储管理：PV, PVC

命名空间：Namespace

// TODO 核心资源关系图

## 调度资源

无状态：Deployment，Java/PHP/Go

有状态：StatefulSet，Eureka/Kafka/Nacos/Zookeeper/MySQL

守护进程：DaemonSet，Filebeat/Fluentd/NodeExporter

计划任务：Job&CronJob，备份/定期任务

## 服务发布

用户->Ingress Controller->Service->Deployment->Pod

外部通过 Ingress 访问

内部通过 Service 访问

## 配置管理

需求：开发环境/测试环境/生产环境需要不同的配置，不同的MySQL/Redis

## 资源隔离

使用命名空间进行资源隔离

