# kubectl 命令基础

kubectl 是 Kubernetes 的官方命令行客户端。它不通过 SSH 直接管理工作节点或容器，而是读取本地 kubeconfig，向 kube-apiserver 发起 HTTP 请求。创建、更新和删除请求由 API Server 校验并保存为资源对象，随后控制器和 kubelet 根据对象状态完成调度与运行；查询请求则读取 API Server 提供的对象和状态信息。第 06 章的 [kube-apiserver](../06-集群架构/4-控制节点组件.md#kube-apiserver) 说明了这条控制面边界。

## 命令结构

面向资源的 kubectl 命令通常遵循以下形式：

```bash
kubectl <command> <type> <name> [flags]
```

```bash
kubectl get deploy nginx --show-labels
kubectl get po -n kube-system -o wide
kubectl delete svc nginx
```

| 部分 | 含义 | 示例 |
| --- | --- | --- |
| `<command>` | 对资源执行的动作 | `get`、`create`、`apply`、`delete` |
| `<type>` | API 资源类型 | `po`、`deploy`、`svc` |
| `<name>` | 某个资源对象的名称，可省略 | `nginx` |
| `[flags]` | 影响请求范围、输出或行为的选项 | `-n`、`-o yaml`、`--show-labels` |

并非每个子命令都接受资源类型和名称。例如 `kubectl config` 管理的是本地 kubeconfig，而 `kubectl version` 查询客户端和服务端版本。对 `get` 等资源查询命令而言，省略名称通常表示列出请求范围内该类型的全部对象。

## API 资源、Kind 与简称

Kubernetes API 用资源对象描述集群状态。YAML 中的 `kind: Pod` 表示对象类型是 Pod；kubectl 命令中的 `po`、`pod` 或 `pods` 表示访问 Pod 这一 API 资源。Kind 用于确定对象结构，API 资源名称用于定位对应的 API 端点，两者相关但不是同一个字段。

资源类型可以使用单数、复数或 API 注册的短名称：

```bash
kubectl get pod
kubectl get pods
kubectl get po
```

本文档中的 kubectl 命令优先使用内置短资源名：

| 完整资源 | 内置短名称 | 常见用途 |
| --- | --- | --- |
| `pods` | `po` | 查看和调试应用实例 |
| `deployments` | `deploy` | 管理无状态工作负载 |
| `services` | `svc` | 查看稳定访问入口 |
| `namespaces` | `ns` | 管理资源作用域 |
| `configmaps` | `cm` | 管理普通配置 |
| `nodes` | `no` | 查看节点状态 |
| `events` | `ev` | 查询运行事件 |
| `endpoints` | `ep` | 查看旧版 Service 后端对象 |

Secret 没有内置短名称。API 组用于组织相关资源，版本用于标识该组在当前集群中提供的对象结构。`kubectl api-resources` 列出当前集群实际支持的资源名称、API 组、版本、Kind、短名称和作用域；它也是确认 CRD（CustomResourceDefinition，用于向集群注册自定义 API 资源）是否已注册的入口：

```bash
kubectl api-resources
kubectl api-resources --namespaced=true
kubectl api-resources --namespaced=false
```

- `--namespaced=true` 只列出需要 Namespace 的资源。
- `--namespaced=false` 列出 Node、PV、StorageClass 等集群级资源。

资源是否属于 Namespace 由 API 定义决定，并不是由 kubectl 命令决定。

## Namespace

Namespace 为命名空间级对象提供名称作用域和管理范围。`dev` 中的 `api` Deployment 与 `prod` 中的同名 Deployment 可以共存；但同一个 Namespace 中不能创建两个同类型、同名称的对象。

```bash
kubectl get po
kubectl get po -n kube-system
kubectl get po --namespace kube-system
kubectl get po -A
```

- `-n` 或 `--namespace` 指定单次请求的 Namespace。
- `-A` 或 `--all-namespaces` 适合 `get` 等查询命令，用于跨 Namespace 列出资源。

## kubeconfig 与上下文

kubeconfig 是 kubectl 的本地访问配置，不是集群中的 Kubernetes 资源。它可以保存多个集群地址、认证身份和 context；context 将一个 `cluster`、一个 `user` 和一个默认 `namespace` 组合为便于切换的操作目标。切换 context 等于同时切换后续请求所用的集群、身份和默认 Namespace。

下面只是 kubeconfig 的 context 片段，不是可直接使用的完整 kubeconfig：

```yaml{2-5}
contexts:
  - name: dev-admin
    context:
      cluster: learning-cluster
      user: admin
      namespace: dev
```

```bash
kubectl config get-contexts
kubectl config current-context
kubectl config use-context <context-name>
kubectl config view --minify
```

### 从控制面节点导入集群

如果只有控制面节点 `master` 保存了 kubeadm 生成的 `/etc/kubernetes/admin.conf`，本地不能只靠 context 配置连接集群。本地还必须拥有 API Server 地址、受信任的 CA 信息和可用身份凭据；`admin.conf` 已包含这些内容，因此可以作为本地临时管理员访问配置的来源。

> [!WARNING]
> `admin.conf` 包含高权限管理员凭据。只从可信控制面节点获取它，传输和保存时限制访问权限，不要提交到仓库、发送到聊天工具或复制给无关人员。日常使用更应创建最小权限的独立用户 kubeconfig，而不是长期复用管理员配置。

以下示例使用具有 `sudo` 权限的 `yleoer@master` 获取控制面配置。`scp` 不能在远端自动通过 `sudo` 读取受限文件，因此使用 SSH 在控制面节点执行 `sudo cat`，再将标准输出写入本地文件；不要为方便传输而放宽 `/etc/kubernetes/admin.conf` 的全局读取权限。

::: code-group

```bash [Linux]
mkdir -p ~/.kube
chmod 700 ~/.kube
ssh yleoer@master 'sudo cat /etc/kubernetes/admin.conf' > ~/.kube/master-admin.conf
chmod 600 ~/.kube/master-admin.conf
```

```powershell [Windows PowerShell]
New-Item -ItemType Directory -Force -Path "$HOME\.kube" | Out-Null
ssh yleoer@master 'sudo cat /etc/kubernetes/admin.conf' |
  Set-Content -Path "$HOME\.kube\master-admin.conf" -Encoding utf8
```

:::

Windows PowerShell 需要已安装并启用 OpenSSH Client，`ssh` 命令才可用。远端 `sudo` 可能要求输入 `yleoer` 的密码；认证提示和错误信息应输出到标准错误，不能混入 kubeconfig 内容。

导入的文件已经包含 `cluster`、`user` 和 context 条目。要让 context 出现在不带 `--kubeconfig` 的 `kubectl config get-contexts` 中，需要将其合并到 kubectl 默认读取的 `~/.kube/config`。下列 `KUBECONFIG` 仅用于执行一次合并；`--flatten --raw` 会将合并结果写成独立文件，并保留连接 API Server 所需的证书和凭据数据。

先查看导入文件包含的 context，再合并到默认配置。Linux 的 `KUBECONFIG` 只作用于紧随其后的合并命令；PowerShell 在 `try` 块结束后恢复原有环境变量。合并成功后删除临时导入文件：

::: code-group

```bash [Linux]
kubectl --kubeconfig="$HOME/.kube/master-admin.conf" config get-contexts
touch "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"

if KUBECONFIG="$HOME/.kube/config:$HOME/.kube/master-admin.conf" \
  kubectl config view --merge --flatten --raw > "$HOME/.kube/config.merged"; then
  chmod 600 "$HOME/.kube/config.merged"
  mv "$HOME/.kube/config.merged" "$HOME/.kube/config"
  rm "$HOME/.kube/master-admin.conf"
else
  rm -f "$HOME/.kube/config.merged"
  exit 1
fi
```

```powershell [Windows PowerShell]
$defaultConfig = "$HOME\.kube\config"
$importedConfig = "$HOME\.kube\master-admin.conf"
kubectl --kubeconfig=$importedConfig config get-contexts
if (-not (Test-Path -LiteralPath $defaultConfig)) {
  New-Item -ItemType File -Path $defaultConfig | Out-Null
}

$previousKubeconfig = $env:KUBECONFIG
try {
  $env:KUBECONFIG = "$defaultConfig;$importedConfig"
  kubectl config view --merge --flatten --raw |
    Set-Content -Path "$defaultConfig.merged" -Encoding utf8
  if ($LASTEXITCODE -ne 0) {
    throw "kubeconfig 合并失败"
  }
  Copy-Item -Force -Path "$defaultConfig.merged" -Destination $defaultConfig
  Remove-Item -Force "$defaultConfig.merged", $importedConfig
} catch {
  Remove-Item -Force -ErrorAction SilentlyContinue "$defaultConfig.merged"
  throw
} finally {
  if ($null -eq $previousKubeconfig) {
    Remove-Item Env:KUBECONFIG -ErrorAction SilentlyContinue
  } else {
    $env:KUBECONFIG = $previousKubeconfig
  }
}
```

:::

合并时，`KUBECONFIG` 路径列表中靠前的文件优先保留同名的 cluster、user 和 context。因此，先对比默认配置和导入文件的名称；若已存在同名对象，不应直接合并，以免导入的 context 引用到已有集群或身份。多集群场景应先为导入文件中的对象使用唯一名称，再执行合并。

合并成功后，从 `kubectl config get-contexts` 输出的 `NAME` 列取得 context 名称。`--context` 只覆盖当前命令的请求目标，不会修改全局 `current-context`：

```bash
kubectl config get-contexts
kubectl --context=<imported-context-name> get no
kubectl --context=<imported-context-name> get po -A
```

`NAME` 是本地 kubeconfig 中 context 的名称，可以按集群和身份重命名。例如，导入配置的 context 名称为 `kubernetes-admin@kubernetes` 时，将其改为 `casa18-admin`：

```bash
kubectl config rename-context kubernetes-admin@kubernetes casa18-admin
kubectl --context=casa18-admin get no
```

该操作只修改 context 名称，不会修改其引用的 cluster 或 user。多集群合并时，三类对象都必须使用唯一名称；仅重命名 context 仍可能让不同集群共享错误的 API Server 地址或管理员凭据。同一个名称可以分别用于 cluster、user 和 context，因为三者位于 kubeconfig 的不同对象集合：

| kubeconfig 对象 | `casa18` 集群的推荐名称 | 作用 |
| --- | --- | --- |
| cluster | `casa18` | 保存 API Server 地址、CA 与 TLS 连接配置。 |
| user | `casa18` 或 `casa18-admin` | 保存用于访问该集群的认证凭据。名称只是本地别名，不会改变证书代表的 Kubernetes 身份。 |
| context | `casa18` 或 `casa18-admin` | 将 cluster、user 与默认 Namespace 组合为一次请求的目标。 |

例如，当前默认 kubeconfig 已包含 Docker Desktop 和名称为 `kubernetes-admin@kubernetes` 的 kubeadm 管理员 context。下面的操作从该 context 读取已嵌入的 CA、客户端证书和私钥，创建名称均为 `casa18` 的新条目；不修改 Docker Desktop，也不切换 `current-context`。代码中的临时文件包含管理员凭据，脚本结束时会删除。

::: code-group

```bash [Linux]
set -euo pipefail

default_config="$HOME/.kube/config"
old_context="kubernetes-admin@kubernetes"
new_cluster="casa18"
new_user="casa18"
new_context="casa18"
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

old_cluster=$(kubectl --kubeconfig="$default_config" --context="$old_context" config view --minify -o jsonpath='{.contexts[0].context.cluster}')
old_user=$(kubectl --kubeconfig="$default_config" --context="$old_context" config view --minify -o jsonpath='{.contexts[0].context.user}')
server=$(kubectl --kubeconfig="$default_config" --context="$old_context" config view --minify --raw -o jsonpath='{.clusters[0].cluster.server}')

kubectl --kubeconfig="$default_config" --context="$old_context" config view --minify --flatten --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 --decode > "$temp_dir/ca.crt"
kubectl --kubeconfig="$default_config" --context="$old_context" config view --minify --flatten --raw -o jsonpath='{.users[0].user.client-certificate-data}' | base64 --decode > "$temp_dir/admin.crt"
kubectl --kubeconfig="$default_config" --context="$old_context" config view --minify --flatten --raw -o jsonpath='{.users[0].user.client-key-data}' | base64 --decode > "$temp_dir/admin.key"

kubectl --kubeconfig="$default_config" config set-cluster "$new_cluster" --server="$server" --certificate-authority="$temp_dir/ca.crt" --embed-certs=true
kubectl --kubeconfig="$default_config" config set-credentials "$new_user" --client-certificate="$temp_dir/admin.crt" --client-key="$temp_dir/admin.key" --embed-certs=true
kubectl --kubeconfig="$default_config" config set-context "$new_context" --cluster="$new_cluster" --user="$new_user"
kubectl --kubeconfig="$default_config" --context="$new_context" get no
```

```powershell [Windows PowerShell]
$defaultConfig = "$HOME\.kube\config"
$oldContext = "kubernetes-admin@kubernetes"
$newCluster = "casa18"
$newUser = "casa18"
$newContext = "casa18"

$source = kubectl --kubeconfig=$defaultConfig --context=$oldContext config view --minify --flatten --raw -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
  throw "无法读取原 context"
}
$cluster = $source.clusters[0].cluster
$user = $source.users[0].user
if (-not $cluster.'certificate-authority-data' -or -not $user.'client-certificate-data' -or -not $user.'client-key-data') {
  throw "该 context 未使用 kubeadm admin.conf 的嵌入式证书凭据"
}

$tempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "kubeconfig-$([guid]::NewGuid())"
[System.IO.Directory]::CreateDirectory($tempDirectory) | Out-Null
try {
  $caFile = Join-Path $tempDirectory "ca.crt"
  $certificateFile = Join-Path $tempDirectory "admin.crt"
  $keyFile = Join-Path $tempDirectory "admin.key"
  [System.IO.File]::WriteAllBytes($caFile, [Convert]::FromBase64String($cluster.'certificate-authority-data'))
  [System.IO.File]::WriteAllBytes($certificateFile, [Convert]::FromBase64String($user.'client-certificate-data'))
  [System.IO.File]::WriteAllBytes($keyFile, [Convert]::FromBase64String($user.'client-key-data'))

  kubectl --kubeconfig=$defaultConfig config set-cluster $newCluster --server=$cluster.server --certificate-authority=$caFile --embed-certs=true
  kubectl --kubeconfig=$defaultConfig config set-credentials $newUser --client-certificate=$certificateFile --client-key=$keyFile --embed-certs=true
  kubectl --kubeconfig=$defaultConfig config set-context $newContext --cluster=$newCluster --user=$newUser
  kubectl --kubeconfig=$defaultConfig --context=$newContext get no
} finally {
  Remove-Item -Force -Recurse -ErrorAction SilentlyContinue $tempDirectory
}
```

:::

新 context 验证成功后，旧的 generic 条目仍会保留，便于回退。确认没有其他 context 引用 `$old_cluster` 和 `$old_user` 后，才可以删除旧 context、cluster 与 user：

```bash
kubectl config delete-context kubernetes-admin@kubernetes
kubectl config unset clusters.kubernetes
kubectl config unset users.kubernetes-admin
```

此处的 `kubernetes` 和 `kubernetes-admin` 是当前示例中旧 cluster 与 user 的实际名称；清理前必须以 `kubectl config get-contexts` 和原 context 的配置为准，不能照抄到名称不同的配置中。使用 kubeadm `admin.conf` 导入第二个及后续集群前，应先在独立 kubeconfig 中创建这组唯一名称，再与默认配置合并。本文前述合并命令仅适用于导入文件与默认配置不存在同名对象的情况。

如果 `get no` 无法连接，先检查该 context 记录的 API Server 地址。控制面本地配置若使用 `127.0.0.1`，在其他机器上必然不可达。此时在默认 kubeconfig 中把对应 cluster 的 `server` 改为可从本机访问的控制面 IP、DNS 名称或负载均衡地址：

```bash
kubectl --context=<imported-context-name> config view --minify -o jsonpath='{.clusters[0].name}'
kubectl --context=<imported-context-name> config view --minify -o jsonpath='{.clusters[0].cluster.server}'
kubectl config set-cluster <cluster-name> --server=https://<control-plane-endpoint>:6443
```

`<control-plane-endpoint>` 必须网络可达，且 API Server 证书的 Subject Alternative Name 必须包含该 IP 或 DNS 名称；否则请求会因 TLS 证书校验失败而被拒绝。kubeadm 集群宜在初始化时通过 `--control-plane-endpoint` 设置稳定入口，避免后续客户端依赖某一台控制面节点的临时地址。

可以为当前 context 设置默认 Namespace：

```bash
kubectl config set-context --current --namespace=dev
kubectl get po
kubectl get po -n dev
```

> [!CAUTION]
> 切换 context 或修改其默认 Namespace 会影响后续所有 kubectl 命令。对生产集群执行变更前，应先使用 `kubectl config current-context` 和 `kubectl config view --minify` 确认目标；临时操作时优先显式传入 `-n <namespace>`。

## 输出与对象状态

kubectl 的输出格式决定观察角度，不会改变资源对象：

```bash
kubectl get po -o wide
kubectl get po nginx -o yaml
kubectl get po nginx -o json
kubectl get po -o name
```

| 格式 | 展示内容 | 适用场景 |
| --- | --- | --- |
| 默认表格 | kubectl 选择的摘要列 | 快速查看资源数量和主要状态 |
| `wide` | 增加 Pod IP、Node 等扩展列 | 初步定位调度和网络位置 |
| `yaml` 或 `json` | API 对象的详细字段，包括 `spec` 和 `status` | 查看对象定义、状态与脚本处理 |
| `name` | 仅资源类型和名称 | 作为其他批量命令的输入 |

- 对象的 `spec` 是期望状态，通常由用户清单声明；
- `status` 是控制器、kubelet 等组件观察并写回的当前状态。

`kubectl get -o yaml` 同时显示二者，因此不能把它直接当作手写清单模板，后续更新应以版本控制中的期望状态清单为准。

## 操作原则

- 先确认当前 context、Namespace、资源类型和名称，再发起变更。
- 首次提交本地完整清单时使用 `kubectl create -f`；已明确存在且清单已修改时使用 `kubectl apply -f`。
- 查询状态时依次查看摘要、详情、事件和日志，避免只根据单个表格列作结论。
- 不确定 API 字段时使用 `kubectl explain`，不确定资源类型或作用域时使用 `kubectl api-resources`。
- 对清单变更先使用 `kubectl diff -f` 或 dry-run 检查，再执行实际更新。

## 参考

- [kubectl 概览](https://kubernetes.io/docs/reference/kubectl/overview/)
- [kubectl explain 命令参考](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_explain/)
