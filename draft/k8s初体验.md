## Kubectl 命令格式详解

```bash
kubectl [command] [TYPE]     [NAME]  [flags]
kubectl  get      deployment nginx   --show-labels
```

- 不指定 name 查当前namespace所有的

## Kubectl 增删改查命令详解

增：create/apply

删：delete

改：replace/edit/apply

查：get

```bash
kubectl get deploy
kubectl get job --sort-by=.metadata.name
kubectl get deploy nginx
kubectl get deploy -n kube-system
kubectl get deploy nginx -oyaml
kubectl get po -owide

kubectl create deployment nginx
kubectl create deployment nginx --dry-run=client -oyaml

kubectl create job hello --image=registry.cn-beijing.aliyuncs.com/dotbalo/counter:v1 -- echo dotbal
kubectl create -f xxx.yaml

kubectl edit deploy nginx
kubectl replace -f xxx.yaml
kubectl apply -f xxx.yaml

kubectl delete deploy nginx
kubectl delete -f xxx.yaml
```

- deployment 通过 rs 来控制 pod 数量
- --dry-run=client -oyaml > xxx.yaml 可以获取yaml文件
- apply 仅仅创建，replace 仅仅是更新，apply 如果没有则创建，有就更新



## Kubectl 常用命令详解

https://kubernetes.io/zh-cn/docs/reference/kubectl/quick-reference

熟悉为主，参考官方文档

- kubectl 上下文配置，一个config可以配置多个，
  - 使用 use 去切换
  - get-contexts 查看所有集群
  - current-context 当前集群
- 创建对象，apply
- 更新资源，rollout
- 查看日志，logs
- 进入容器，exec -it -- bash
- 拷贝文件 cp
- api-resources, namespace=true/false



## Kubectl explain 助力 yaml 编写

```bash
kubectl explain deploy.metadata
```



## Namespace 概念及主要作用

提供了一种将集群资源逻辑上隔离的方式，允许在同一个集群中划分多个虚拟的/逻辑上独立的集群环境，相当于集群的“虚拟化”。

经常用于多个团队和多个项目的场景，可以按照不同的环境划分namespace，或者按照不同的团队及租户划分namespace。

- 资源隔离：不同团队或项目可以拥有自己独立的namespace，以防止资源相互干扰
- 权限控制：可以为不同的namespace设置不同的访问权限，实现不同的用户具有不同的权限
- 环境拆分：使用namespace可以模拟出多个虚拟的集群环境，如开发/测试和生产环境。每个环境可以有自己的资源和服务，相互之间保持隔离，有助于简化部署和管理
- 资源配额和限制：划分不同的Namespace可以更加有效的分配资源和限制资源的使用量
- 服务发现和负载均衡：在同一个namespace中服务发现和负载均衡更加简单和高效
- 简化管理：拆分不同的namespace，可以更加方便的对namespace下的资源进行操作，比如删除/备份或迁移

## 默认 Namespace 介绍和用途

kubectl get ns 查看所有命名空间

- default: 默认命名空间，在为指定命名空间时，即表示为default
- kube-node-lease：此空间保存与每个节点关联的租约（Lease）对象
- kube-public：公开的命名空间可以被任何用户访问，包括未授权的用户
- kube-system：Kubernetes系统组件所在的命名空间

## Namespace 基本作用

创建 kubectl create ns NAMESPACE_NAME，还可以通过 yaml 创建

删除：kubectl delete ns NAMESPACE_NAME，会强制删除，可能被某个资源卡住

查看：kubectl get ns NAMESPACE_NAME --show-labels

名字限制：最多63个字符，只能包含字母/数字和中横线，并且开头不能是数字

## Pod 概念及Pod架构



## Pod 设计思想及解决的问题



## Pod 基本使用及多容器注意事项



## Pod 常见状态及问题排查通用方法



## K8s 初体验总结及常见面试问题