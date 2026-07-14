# ConfigMap 资源

ConfigMap 用于保存非敏感配置，使配置能够独立于容器镜像更新和复用。ConfigMap 不保证应用自动加载新配置，也不提供敏感数据保护。

## 资源结构

ConfigMap 的 `data` 保存 UTF-8 字符串，`binaryData` 保存 Base64 编码的二进制数据。同一个键不能同时出现在两个字段中。

```yaml [app-config.yaml]
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  APP_MODE: "production"
  HTTP_PORT: "8080"
  app.yaml: |-
    server:
      address: 0.0.0.0
      port: 8080
binaryData:
  banner.bin: AQIDBA==
```

`data` 中的标量最终都是字符串。YAML 中容易被解释为数字、布尔值或日期的内容应加引号，例如 `"8080"`、`"true"`。

首次创建并查看对象：

```bash
kubectl create -f app-config.yaml
kubectl get cm app-config
kubectl describe cm app-config
kubectl get cm app-config -o yaml
```

ConfigMap 名称必须是合法的 DNS 子域名；键名只能包含字母、数字、`-`、`_` 或 `.`。每个对象的数据总量不能超过 1 MiB。

## 从字面量创建

少量键值可以直接通过命令创建：

```bash
kubectl create cm runtime-config \
  --from-literal=LOG_LEVEL=info \
  --from-literal=WORKERS=4
```

命令式创建适合临时验证。需要长期维护的配置应保留声明式清单或原始配置文件，避免集群内对象成为唯一副本。

## 从环境文件创建

`--from-env-file` 按 `KEY=VALUE` 读取文件，每一行生成一个 ConfigMap 键值。文件内容如下：

```dotenv [app.env]
DB_HOST=postgres.default.svc.cluster.local
DB_PORT=5432
DB_NAME=app
```

创建并查看：

```bash
kubectl create cm database-config --from-env-file=app.env
kubectl get cm database-config -o yaml
```

生成后的 `data` 是 `DB_HOST: ...` 这类 YAML 键值映射，不会保留 `=` 号。空行和以 `#` 开头的注释行会被忽略。

## 从文件创建

以下 Nginx 配置文件作为 ConfigMap 的输入：

```nginx [default.conf]
server {
    listen 8080;
    server_name _;

    location /healthz {
        access_log off;
        return 200 "ok\n";
    }
}
```

默认以文件名作为键：

```bash
kubectl create cm nginx-config --from-file=default.conf
```

也可以显式指定键名，或一次读取多个文件：

```bash
kubectl create cm nginx-config-named \
  --from-file=nginx.conf=default.conf

kubectl create cm service-config \
  --from-file=default.conf \
  --from-env-file=app.env
```

`--from-file=<目录>` 只读取目录第一层中键名合法的常规文件，不递归读取子目录，也会忽略符号链接、设备和管道等条目。目录中存在包含非法字符的文件名时，kubectl 可能创建失败且不一定打印明确错误，执行前应先检查文件名。

## 生成清单

需要先审阅或纳入版本管理时，可以让 kubectl 只在客户端生成 YAML：

```bash
kubectl create cm nginx-config \
  --from-file=default.conf \
  --dry-run=client -o yaml
```

这里不直接创建 API 对象。确认生成内容后再保存为声明式清单，并在第一次提交到集群时使用 `kubectl create -f`。

## 不可变 ConfigMap

稳定配置可以设置 `immutable: true`，防止意外修改 `data` 和 `binaryData`：

```yaml [immutable-config.yaml]
apiVersion: v1
kind: ConfigMap
metadata:
  name: immutable-config
immutable: true
data:
  FEATURE_MODE: "stable"
```

```bash
kubectl create -f immutable-config.yaml
```

`immutable` 从 `false` 改为 `true` 后不能恢复，也不能再修改数据，只能删除并重建对象。已有 Pod 对被删除对象的挂载点仍然存在，因此替换不可变 ConfigMap 时通常使用带版本的名称并滚动更新工作负载。

## 更新方式

声明式清单已经存在且内容发生修改时，可以更新：

```bash
kubectl apply -f app-config.yaml
```

也可以直接编辑集群内对象：

```bash
kubectl edit cm app-config
```

直接编辑不利于追踪配置来源。长期配置更适合在版本库中维护清单，并通过评审后的发布流程更新。
