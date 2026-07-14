# Kubectl 增删改查命令详解

Kubernetes 中的资源对象通常通过 kubectl 完成增删改查。常见操作可以归纳为四类：创建、查看、修改和删除。

## 创建资源

第一次创建资源使用 `create`。命令式创建适合快速生成简单资源，基于完整清单创建的方式在下一小节记录。

```bash
kubectl create deploy nginx --image=nginx:1.31-alpine
kubectl create ns dev
```

资源已存在时，`create` 会报错。`apply` 虽然也能创建不存在的资源，但本文只把它用于修改已经由清单创建的资源，使首次创建和后续更新的意图保持清晰。

## 生成 YAML 清单

很多资源可以先通过命令生成 YAML，再手动调整字段：

```bash
kubectl create deploy nginx --image=nginx:1.31-alpine --dry-run=client -o yaml
kubectl create ns dev --dry-run=client -o yaml
kubectl create job hello --image=busybox:1.38 --dry-run=client -o yaml -- echo hello
```

生成命令可以作为起点。整理后的完整 `nginx-deploy.yaml` 如下：

```yaml [nginx-deploy.yaml]
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.31-alpine
```

首次提交该清单：

```bash
kubectl create -f nginx-deploy.yaml
```

`--dry-run=client` 表示只在客户端生成对象，不提交到 APIServer；`-o yaml` 表示以 YAML 格式输出。保存后应检查并整理完整清单，再使用 `create -f` 创建资源。

## 查看资源

查询资源使用 `get`：

```bash
kubectl get deploy
kubectl get deploy nginx
kubectl get deploy nginx -o yaml
kubectl get po -o wide
kubectl get po -A
kubectl get job --sort-by=.metadata.name
```

常用查看方式如下：

| 命令                                | 作用                   |
|-----------------------------------|----------------------|
| `kubectl get po`                 | 查看当前 Namespace 的 Pod |
| `kubectl get po -A`              | 查看所有 Namespace 的 Pod |
| `kubectl get po -o wide`         | 查看更多运行信息             |
| `kubectl get po nginx -o yaml`   | 查看完整资源定义             |
| `kubectl get deploy -l app=nginx` | 按标签查询 Deployment     |

## 查看详情

`describe` 用于查看资源详情、事件和部分状态解释：

```bash
kubectl describe po nginx
kubectl describe deploy nginx
kubectl describe no worker-01
```

`get -o yaml` 更适合查看完整的资源对象；`describe` 更适合排查问题，尤其是调度失败、镜像拉取失败、健康检查失败等场景。

## 修改资源

修改资源常用 `apply`、`edit`、`replace` 和少量专用命令。下面的 `nginx-deploy.yaml` 复用前文[生成 YAML 清单](#生成-yaml-清单)中的完整文件，并假设 Deployment 已经创建：

```bash
kubectl apply -f nginx-deploy.yaml
kubectl edit deploy nginx
kubectl replace -f nginx-deploy.yaml
kubectl scale deploy nginx --replicas=3
kubectl set image deploy/nginx nginx=nginx:1.31-alpine
kubectl patch deploy nginx -p '{"spec":{"replicas":2}}'
```

几种方式的区别如下：

| 命令          | 特点        | 适用场景                        |
|-------------|-----------|-----------------------------|
| `apply`     | 按修改后的清单更新已有资源 | 已纳入 YAML 管理的资源               |
| `edit`      | 在线编辑当前资源  | 临时修改和排查                     |
| `replace`   | 用文件替换已有资源 | 明确知道完整资源定义时使用               |
| `scale`     | 调整副本数     | Deployment、StatefulSet 等扩缩容 |
| `set image` | 修改容器镜像    | 快速发版或测试                     |
| `patch`     | 按补丁更新部分字段 | 脚本化修改单个或少量字段                |

`patch` 默认使用 strategic merge patch，也可以通过 `--type` 指定 JSON merge patch 或 JSON patch。

生产环境更推荐把资源配置写入 YAML，首次使用 `create`，后续修改使用 `apply`，这样配置的每次变更都能纳入版本管理。

## 删除资源

删除资源使用 `delete`：

```bash
kubectl delete deploy nginx
kubectl delete po nginx
kubectl delete -f nginx-deploy.yaml
kubectl delete ns dev
```

删除前建议先确认资源：

```bash
kubectl get deploy nginx
kubectl get po -l app=nginx
```

如果资源由 Deployment、StatefulSet 等控制器管理，不建议直接删除它创建的 Pod，因为控制器会根据期望副本数将其重新拉起。

## apply 与 replace 的区别

`apply` 是常用的声明式更新方式：

- 命令本身可以创建不存在的资源，但本文约定首次创建使用 `create`
- 已存在的资源会被更新
- 适合长期维护 YAML 清单

`replace` 更像“用当前文件替换线上对象”：

- 资源必须已经存在
- 文件需要包含完整对象定义
- 不适合作为默认更新方式

实际工作中，建议先用 `create -f` 提交完整清单，后续把 `apply -f` 作为更新入口；`edit` 用于临时调整，`replace` 用于明确的替换场景。
