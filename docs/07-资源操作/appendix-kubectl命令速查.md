# kubectl 命令速查

本附录只汇总第 07 章高频命令，不重复解释 Kubernetes 概念。context、Namespace、清单更新、事件和 Pod 状态的语义应分别回到正文确认。

## 操作前确认

相关概念见[kubeconfig 与上下文](./1-kubectl命令基础.md#kubeconfig-与上下文)和[Namespace](./4-Namespace基本使用.md#名称作用域与资源范围)。

| 命令 | 用途 |
| --- | --- |
| `kubectl config current-context` | 确认当前操作的 context |
| `kubectl config view --minify` | 查看当前 context 的集群、身份和默认 Namespace |
| `kubectl get ns` | 确认目标 Namespace 是否存在 |
| `kubectl api-resources` | 查询集群支持的资源类型、短名称和作用域 |

## 查询与筛选

相关概念见[资源查询与排障](./3-资源查询与排障.md#资源列表与详情)。

| 命令 | 用途 |
| --- | --- |
| `kubectl get po -n <namespace>` | 查看指定 Namespace 的 Pod |
| `kubectl get po -A` | 查看全部 Namespace 中的 Pod |
| `kubectl get po -o wide` | 查看 Pod IP、Node 等扩展列 |
| `kubectl get po -l app=<name>` | 按 Label 筛选 Pod |
| `kubectl describe po <pod-name>` | 查看 Pod 详情和关联 Event |
| `kubectl get ev --sort-by=.metadata.creationTimestamp` | 按时间查看近期事件 |

## 清单操作

下列 `nginx-deploy.yaml` 复用[资源创建与更新](./2-资源创建与更新.md#生成并整理清单)中的完整清单；`create`、`diff`、`apply` 和 dry-run 的语义见[声明式更新](./2-资源创建与更新.md#声明式更新)。

| 命令 | 用途 |
| --- | --- |
| `kubectl create -f nginx-deploy.yaml` | 首次提交清单 |
| `kubectl diff -f nginx-deploy.yaml` | 预览已修改清单与集群对象的差异 |
| `kubectl apply -f nginx-deploy.yaml` | 更新已创建且已修改的清单 |
| `kubectl apply --dry-run=server -f nginx-deploy.yaml` | 请求服务端校验但不持久化变更 |
| `kubectl delete -f nginx-deploy.yaml` | 根据清单删除资源 |

## 日志与容器观察

相关概念见[日志、事件与命令执行](./3-资源查询与排障.md#日志事件与命令执行)和[Pod 状态模型](./5-Pod创建与状态观察.md#pod-状态模型)。

| 命令 | 用途 |
| --- | --- |
| `kubectl logs <pod-name>` | 查看默认容器日志 |
| `kubectl logs <pod-name> -c <container-name>` | 查看指定容器日志 |
| `kubectl logs <pod-name> --previous` | 查看上一轮已终止容器日志 |
| `kubectl exec -it <pod-name> -- sh` | 在运行中的容器内执行 shell |
| `kubectl explain po.spec.containers` | 查询 Pod 容器字段说明 |

> [!CAUTION]
> 执行 `delete`、`apply`、`patch` 或 `scale` 前，先确认 context、Namespace、资源类型和名称。对由控制器管理的 Pod，不要以删除 Pod 作为缩容手段。
