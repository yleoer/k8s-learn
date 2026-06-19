# Kubectl 常用命令详解

kubectl 常用命令大致可以分为集群连接、资源查看、日志排查、容器调试、文件传输、发布观察和字段查询几类。初学阶段不必记住所有参数，但要熟悉这些常见的操作入口。

## 查看集群信息

连接集群后，可以先确认集群基本信息：

```bash
kubectl cluster-info
kubectl version
kubectl get nodes
```

常见用途如下：

| 命令 | 作用 |
| --- | --- |
| `kubectl cluster-info` | 查看控制面访问地址 |
| `kubectl version` | 查看客户端和服务端版本 |
| `kubectl get nodes` | 查看工作节点状态 |

如果 `kubectl version` 只能看到客户端版本，通常说明 kubectl 没有成功连接到 APIServer。

## kubeconfig 与上下文

kubeconfig 用来保存集群地址、用户认证信息、Namespace 和上下文。一个 kubeconfig 可以配置多个集群。

```bash
kubectl config get-contexts
kubectl config current-context
kubectl config use-context <context-name>
```

| 命令 | 作用 |
| --- | --- |
| `get-contexts` | 查看 kubeconfig 中的所有上下文 |
| `current-context` | 查看当前正在使用的上下文 |
| `use-context` | 切换到指定上下文 |

上下文切换会影响后续所有 kubectl 命令，因此生产环境操作前必须确认当前上下文，避免误操作到错误的集群。

## 设置默认 Namespace

可以为当前上下文设置默认 Namespace：

```bash
kubectl config set-context --current --namespace=dev
kubectl config view --minify
```

设置后，下面两条命令含义一致：

```bash
kubectl get pod
kubectl get pod -n dev
```

如果只是临时查询，建议直接用 `-n` 指定 Namespace；如果长期在某个环境工作，则可以为上下文设置默认 Namespace。

## 查看资源列表

最常用的查看命令是 `get`：

```bash
kubectl get pod
kubectl get deployment
kubectl get service
kubectl get namespace
kubectl get pod -A
```

常见组合如下：

```bash
kubectl get pod,svc
kubectl get all
kubectl get all -n dev
```

`kubectl get all` 只会展示一组常见资源，并不等于集群中的所有资源。要查看完整的资源类型清单，应使用 `kubectl api-resources`。

## 输出格式与字段观察

排查时经常需要更详细的输出：

```bash
kubectl get pod -o wide
kubectl get service -o wide
kubectl get deployment nginx -o yaml
kubectl get pod nginx -o json
```

`-o wide` 适合快速查看扩展列，如 Pod IP、所在 Node、镜像等；`-o yaml` 适合查看完整的资源字段和当前状态。

## 标签筛选

Kubernetes 很多资源通过标签建立关联。可以使用 `-l` 按标签筛选：

```bash
kubectl get pod -l app=nginx
kubectl get pod -l app=nginx,tier=frontend
kubectl get service -l app=nginx --show-labels
```

常见标签筛选表达式：

```bash
kubectl get pod -l 'app in (nginx,redis)'
kubectl get pod -l 'env!=prod'
kubectl get pod -l 'app'
```

标签是 Deployment、Service、Pod 关联关系中的关键线索。排查 Service 后端为空时，通常要先检查标签选择器是否匹配。

## 字段筛选

字段筛选适合按资源自身字段查询：

```bash
kubectl get pod --field-selector status.phase=Running
kubectl get pod --field-selector status.phase=Pending
kubectl get event --field-selector type=Warning
```

字段筛选支持的字段因资源类型而异。初学阶段，常用它来快速找出异常 Pod 或 Warning 事件。

## 排序输出

可以通过 `--sort-by` 按指定字段排序：

```bash
kubectl get pod --sort-by=.metadata.name
kubectl get pod --sort-by=.metadata.creationTimestamp
kubectl get job --sort-by=.metadata.name
```

字段路径来自资源对象本身，可以先通过 `kubectl get <type> <name> -o yaml` 查看字段结构。

## 查看日志

查看容器日志使用 `logs`：

```bash
kubectl logs nginx
kubectl logs nginx -c nginx
kubectl logs nginx --tail=100
kubectl logs nginx -f
kubectl logs nginx --previous
```

常用参数如下：

| 参数 | 作用 |
| --- | --- |
| `-c` | 指定 Pod 中的容器名称 |
| `--tail` | 查看最后若干行日志 |
| `-f` | 持续追踪日志 |
| `--previous` | 查看上一次容器实例的日志 |
| `--since` | 查看最近一段时间的日志 |

当 Pod 处于 `CrashLoopBackOff` 时，`--previous` 尤其有用：当前容器可能刚启动就退出，上一轮的日志往往更接近真实的失败原因。

## 进入容器

进入容器执行命令使用 `exec`：

```bash
kubectl exec -it nginx -- sh
kubectl exec -it nginx -- bash
kubectl exec -it nginx -c nginx -- sh
kubectl exec nginx -- env
```

`--` 后面的内容是在容器内执行的命令。很多精简镜像没有 `bash`，此时可以改用 `sh`。

## 文件拷贝

kubectl 支持在本地和容器之间复制文件：

```bash
kubectl cp ./index.html nginx:/usr/share/nginx/html/index.html
kubectl cp nginx:/var/log/nginx/access.log ./access.log
kubectl cp ./config.yaml dev/nginx:/app/config.yaml -c app
```

格式说明：

```bash
kubectl cp <本地路径> <namespace>/<pod>:<容器路径>
kubectl cp <namespace>/<pod>:<容器路径> <本地路径>
```

`kubectl cp` 依赖容器内的 `tar` 等归档工具。生产中更推荐通过镜像、ConfigMap、Secret 或 PVC 管理文件，而不是频繁手工复制。

## 查看事件

事件是 Kubernetes 排障的重要线索：

```bash
kubectl get events
kubectl get events -n dev
kubectl get events --sort-by=.metadata.creationTimestamp
kubectl get events --field-selector type=Warning
```

常见事件可以帮助判断 Pod 是否调度失败、镜像是否拉取失败、健康检查是否失败、卷是否挂载失败、节点资源是否不足。

## 资源发现

集群支持哪些资源，可以通过 `api-resources` 查询：

```bash
kubectl api-resources
kubectl api-resources --namespaced=true
kubectl api-resources --namespaced=false
```

查看 API 版本使用：

```bash
kubectl api-versions
```

安装 CRD 或 Operator 后，新增的自定义资源通常也能通过 `api-resources` 看到。

## 发布与回滚观察

Deployment 等工作负载资源可以使用 `rollout` 查看发布状态：

```bash
kubectl rollout status deployment/nginx
kubectl rollout history deployment/nginx
kubectl rollout undo deployment/nginx
kubectl rollout restart deployment/nginx
```

初体验阶段只需要知道它们的用途：

| 命令 | 作用 |
| --- | --- |
| `rollout status` | 查看发布是否完成 |
| `rollout history` | 查看历史版本 |
| `rollout undo` | 回滚到上一版本 |
| `rollout restart` | 触发滚动重启 |

Deployment 章节会进一步分析滚动更新、暂停、恢复和回滚细节。

## 临时调试 Pod

可以使用 `run` 快速启动一个临时 Pod：

```bash
kubectl run test-shell --image=busybox:1.36 -it --rm -- sh
kubectl run nginx --image=nginx:1.25
```

`--rm` 表示退出后删除 Pod，适合临时测试 DNS、网络连通性和镜像拉取。

## explain 查询字段

`kubectl explain` 用于查询资源字段说明，适合辅助编写 YAML：

```bash
kubectl explain pod
kubectl explain pod.spec
kubectl explain pod.spec.containers
kubectl explain deployment.spec.template
kubectl explain pod.spec.containers --recursive
```

使用建议：

- 不确定字段层级时，先查资源整体，再逐级查看字段
- 递归输出适合快速查看字段树
- 字段说明以当前集群 API 为准
- 写完 YAML 后再使用 `kubectl apply -f <file> --dry-run=client` 做基础检查

`explain` 是一个辅助命令，掌握它的核心价值即可：遇到不熟悉的 YAML 字段时，直接查询字段的路径和含义。

## 常用排障顺序

遇到 Pod 异常时，可以按以下顺序推进：

```bash
kubectl get pod -o wide
kubectl describe pod <pod-name>
kubectl logs <pod-name>
kubectl logs <pod-name> --previous
kubectl get events --sort-by=.metadata.creationTimestamp
```

这套顺序能覆盖大部分初学阶段的问题，包括调度失败、镜像拉取失败、容器启动失败和健康检查失败。
