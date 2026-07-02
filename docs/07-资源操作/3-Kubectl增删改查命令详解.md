# Kubectl 增删改查命令详解

Kubernetes 中的资源对象通常通过 kubectl 完成增删改查。常见操作可以归纳为四类：创建、查看、修改和删除。

## 创建资源

创建资源常用 `create` 和 `apply`。

```bash
kubectl create deployment nginx --image=nginx:1.27
kubectl create namespace dev
kubectl create -f nginx.yaml
kubectl apply -f nginx.yaml
```

`create` 偏向命令式创建，资源已存在时会报错；`apply` 偏向声明式管理，资源不存在时创建，已存在时按配置更新。

## 生成 YAML 清单

很多资源可以先通过命令生成 YAML，再手动调整字段：

```bash
kubectl create deployment nginx --image=nginx:1.27 --dry-run=client -o yaml
kubectl create namespace dev --dry-run=client -o yaml
kubectl create job hello --image=busybox:1.36.1 --dry-run=client -o yaml -- echo hello
```

常见流程如下：

```bash
kubectl create deployment nginx --image=nginx:1.27 --dry-run=client -o yaml > nginx-deploy.yaml
kubectl apply -f nginx-deploy.yaml
```

`--dry-run=client` 表示只在客户端生成对象，不提交到 APIServer；`-o yaml` 表示以 YAML 格式输出。

## 查看资源

查询资源使用 `get`：

```bash
kubectl get deployment
kubectl get deployment nginx
kubectl get deployment nginx -o yaml
kubectl get pod -o wide
kubectl get pod -A
kubectl get job --sort-by=.metadata.name
```

常用查看方式如下：

| 命令 | 作用 |
| --- | --- |
| `kubectl get pod` | 查看当前 Namespace 的 Pod |
| `kubectl get pod -A` | 查看所有 Namespace 的 Pod |
| `kubectl get pod -o wide` | 查看更多运行信息 |
| `kubectl get pod nginx -o yaml` | 查看完整资源定义 |
| `kubectl get deploy -l app=nginx` | 按标签查询 Deployment |

## 查看详情

`describe` 用于查看资源详情、事件和部分状态解释：

```bash
kubectl describe pod nginx
kubectl describe deployment nginx
kubectl describe node worker-01
```

`get -o yaml` 更适合查看完整的资源对象；`describe` 更适合排查问题，尤其是调度失败、镜像拉取失败、健康检查失败等场景。

## 修改资源

修改资源常用 `apply`、`edit`、`replace` 和少量专用命令。

```bash
kubectl apply -f nginx-deploy.yaml
kubectl edit deployment nginx
kubectl replace -f nginx-deploy.yaml
kubectl scale deployment nginx --replicas=3
kubectl set image deployment/nginx nginx=nginx:1.26
```

几种方式的区别如下：

| 命令 | 特点 | 适用场景 |
| --- | --- | --- |
| `apply` | 声明式创建或更新 | 推荐用于 YAML 管理 |
| `edit` | 在线编辑当前资源 | 临时修改和排查 |
| `replace` | 用文件替换已有资源 | 明确知道完整资源定义时使用 |
| `scale` | 调整副本数 | Deployment、StatefulSet 等扩缩容 |
| `set image` | 修改容器镜像 | 快速发版或测试 |

生产环境更推荐把资源配置写入 YAML 并使用 `apply`，这样配置的每次变更都能纳入版本管理。

## 删除资源

删除资源使用 `delete`：

```bash
kubectl delete deployment nginx
kubectl delete pod nginx
kubectl delete -f nginx-deploy.yaml
kubectl delete namespace dev
```

删除前建议先确认资源：

```bash
kubectl get deployment nginx
kubectl get pod -l app=nginx
```

如果资源由 Deployment、StatefulSet 等控制器管理，不建议直接删除它创建的 Pod，因为控制器会根据期望副本数将其重新拉起。

## apply 与 replace 的区别

`apply` 是最常用的声明式操作方式：

- 文件中不存在的资源会被创建
- 已存在的资源会被更新
- 适合长期维护 YAML 清单

`replace` 更像“用当前文件替换线上对象”：

- 资源必须已经存在
- 文件需要包含完整对象定义
- 不适合作为默认更新方式

实际工作中，建议把 `apply -f` 作为主要入口，把 `create` 用于快速生成资源，把 `edit` 用于临时调整，把 `replace` 用于明确的替换场景。
