# Kubectl 命令格式详解

kubectl 是 Kubernetes 的官方命令行工具，用来向 APIServer 发起资源查询、创建、修改、删除、调试和配置切换等请求。理解它的命令格式，是后续操作所有 Kubernetes 资源的基础。

## 基本语法

kubectl 的通用命令格式如下：

```bash
kubectl [command] [TYPE] [NAME] [flags]
```

示例：

```bash
kubectl get deployment nginx --show-labels
kubectl get pod -n kube-system -o wide
kubectl delete service nginx
```

各部分含义如下：

| 部分 | 含义 | 示例 |
| --- | --- | --- |
| `command` | 要执行的操作 | `get`、`create`、`apply`、`delete` |
| `TYPE` | 资源类型 | `pod`、`deployment`、`service` |
| `NAME` | 资源名称，可省略 | `nginx` |
| `flags` | 命令选项 | `-n`、`-o yaml`、`--show-labels` |

不指定 `NAME` 时，通常表示查询当前 Namespace 下该类型的所有资源；指定 `NAME` 时，表示操作某一个具体资源。

## 资源类型写法

Kubernetes 资源类型通常可以使用完整名称、复数名称或短名称：

```bash
kubectl get pod
kubectl get pods
kubectl get po
```

常见资源简称如下：

| 完整资源 | 常用简称 | 说明 |
| --- | --- | --- |
| `pods` | `po` | Pod 资源 |
| `deployments` | `deploy` | Deployment 资源 |
| `services` | `svc` | Service 资源 |
| `namespaces` | `ns` | Namespace 资源 |
| `configmaps` | `cm` | ConfigMap 资源 |
| `secrets` | 无 | Secret 资源 |
| `nodes` | `no` | Node 资源 |

如果忘记资源名称或简称，可以使用 `api-resources` 查询：

```bash
kubectl api-resources
kubectl api-resources --namespaced=true
kubectl api-resources --namespaced=false
```

`--namespaced=true` 用于查看属于 Namespace 的资源，`--namespaced=false` 用于查看集群级资源。

## Namespace 参数

大多数工作负载资源都属于某个 Namespace。默认情况下，kubectl 操作当前上下文中的默认 Namespace，通常是 `default`。

```bash
kubectl get pod
kubectl get pod -n kube-system
kubectl get pod --namespace kube-system
```

`-n` 是 `--namespace` 的缩写。排查问题时，要先确认资源所在 Namespace，否则可能出现“资源不存在”的误判。

## 输出格式

kubectl 默认以表格形式输出。学习和排障时还常用以下格式：

```bash
kubectl get pod -o wide
kubectl get pod nginx -o yaml
kubectl get pod nginx -o json
kubectl get pod -o name
```

| 输出格式 | 适用场景 |
| --- | --- |
| `wide` | 查看更多摘要字段，如 Pod IP、Node |
| `yaml` | 查看完整资源定义，适合学习字段和备份配置 |
| `json` | 适合脚本或工具进一步处理 |
| `name` | 只输出资源类型和名称，适合批量操作 |

## 常用全局参数

以下参数适用于大多数 kubectl 命令：

| 参数 | 作用 |
| --- | --- |
| `-n, --namespace` | 指定 Namespace |
| `-A, --all-namespaces` | 查询所有 Namespace 的资源 |
| `-o` | 指定输出格式 |
| `--show-labels` | 显示资源标签 |
| `-l, --selector` | 按标签筛选资源 |
| `--field-selector` | 按字段筛选资源 |
| `--kubeconfig` | 指定 kubeconfig 文件路径 |
| `--context` | 指定 kubeconfig 中的上下文 |

示例：

```bash
kubectl get pod -A
kubectl get pod -l app=nginx
kubectl get pod --field-selector status.phase=Running
kubectl get deployment --show-labels
```

## 命令使用习惯

生产环境中建议养成以下习惯：

- 操作资源前先用 `kubectl get` 确认 Namespace 和名称
- 修改资源前先用 `kubectl get <type> <name> -o yaml` 查看当前配置
- 删除资源前明确指定资源类型、名称和 Namespace
- 编写脚本时尽量使用完整资源类型，减少简称带来的可读性问题
- 对重要变更先使用 `--dry-run=client -o yaml` 生成或检查资源清单

kubectl 的核心不在于记住所有命令，而在于理解“命令操作资源对象”这一基本结构。
