---
layout: home

hero:
  name: Kubernetes 学习笔记
  text: 从容器基础到集群实践
  tagline: 记录 Docker、容器运行时与 Kubernetes 的系统学习过程

features:
  - icon: 🚀
    title: 一 · 入门起步
    details: 完成环境规划、Ubuntu 节点准备、containerd 组件安装、kubeadm 初始化、Calico 网络和集群验证。
    link: /01-入门起步/
  - icon: 📦
    title: 二 · 容器基石
    details: 梳理容器运行模型、Docker 架构、镜像管理、容器排障、数据持久化和服务部署流程。
    link: /02-容器基础/
  - icon: ⚙️
    title: 三 · K8s 核心资源
    details: Pod、无状态/有状态调度、Service、Ingress、ConfigMap、存储、Job。
    link: /10-K8s核心单元-Pod入门与实战/
  - icon: 🧩
    title: 四 · 综合实战
    details: 把 SpringCloud 项目迁移到 K8s，并做云原生架构升级。
    link: /18-K8s综合练习-SpringCloud项目迁移至K8s/
  - icon: 🎯
    title: 五 · 调度与资源治理
    details: 亲和力、污点容忍、ResourceQuota / LimitRange / QoS、RBAC 权限。
    link: /20-K8s亲和力-提升服务高可用性/
  - icon: 🛠️
    title: 六 · 工程化与弹性
    details: Helm 包管理、Operator 扩展、基于 KEDA 的下一代弹性伸缩。
    link: /26-K8s工程化管理-Helm入门到实战/
  - icon: 📊
    title: 七 · 可观测性
    details: ECK 日志、Prometheus 监控、Alertmanager 告警、Skywalking 链路、服务网格。
    link: /29-K8s可观测性-基于ECK的下一代日志收集框架/
  - icon: 💾
    title: 八 · 分布式存储
    details: EB 级分布式高可用存储平台落地实践。
    link: /34-K8s存储能力-EB级分布式高可用存储平台落地/
  - icon: 🔁
    title: 九 · DevOps 落地
    details: Jenkins 基础与 Pipeline、从零建设 K8s DevOps 平台、Tekton 云原生流水线。
    link: /35-DevOps落地-DevOps及Jenkins基础入门/
  - icon: 🏢
    title: 十 · 企业级落地
    details: 高可用架构、异地多活与智能 DNS、ArgoCD 多集群、备份恢复、简历指导。
    link: /39-K8s企业级高可用架构设计及落地/
---
