# Pod 资源定义与基础配置

Pod 是 Kubernetes 中最小的可部署计算单元，也是调度的基本对象。它并非单纯的“一个容器”，而是一组紧密协作容器的运行环境，统一承载网络、存储、启动命令、环境变量、资源限制、生命周期和健康检查等配置。

## 最小 Pod 示例

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-demo
  labels:
    app.kubernetes.io/name: nginx
    app.kubernetes.io/component: web
spec:
  containers:
    - name: nginx
      image: nginx:stable-alpine
```

创建并查看 Pod：

```bash
kubectl create -f nginx.yaml
kubectl get pod nginx-demo -o wide
kubectl describe pod nginx-demo
```

::: details 输出示例

```bash
$ kubectl get po nginx-demo -owide
NAME         READY   STATUS    RESTARTS   AGE   IP               NODE     NOMINATED NODE   READINESS GATES
nginx-demo   1/1     Running   0          6s    10.244.205.197   work01   <none>           <none>
```

:::

快速测试时也可以使用 `kubectl run`：

```bash
kubectl run nginx-demo --image=nginx:stable-alpine
kubectl run nginx-demo --image=nginx:stable-alpine --dry-run=client -o yaml
```

`kubectl run` 适合临时验证，需要长期保留的资源建议保存为 YAML，并通过声明式方式管理。

## 基础字段说明

| 字段 | 是否必选 | 说明 |
| --- | --- | --- |
| `apiVersion` | 是 | API 版本，Pod 使用 `v1` |
| `kind` | 是 | 资源类型，Pod 固定为 `Pod` |
| `metadata` | 是 | 元数据区域，用于定义 Pod 名称、标签等标识信息 |
| `metadata.name` | 是 | Pod 名称，同一 Namespace 内必须唯一 |
| `metadata.labels` | 否 | Pod 标签，常用于 Service、控制器或运维平台筛选资源 |
| `metadata.labels.app.kubernetes.io/name` | 否 | Kubernetes 推荐标签，表示应用名称，本例为 `nginx` |
| `metadata.labels.app.kubernetes.io/component` | 否 | Kubernetes 推荐标签，表示应用组件类型，本例为 `web` |
| `spec` | 是 | Pod 期望状态定义区域，用于描述容器、存储、调度等配置 |
| `spec.containers` | 是 | 容器列表，至少包含一个容器 |
| `spec.containers[].name` | 是 | 容器名称，同一个 Pod 内必须唯一 |
| `spec.containers[].image` | 是 | 容器镜像地址，本例使用 `nginx:stable-alpine` |

字段不确定时使用：

```bash
kubectl explain pod.spec
kubectl explain pod.spec.containers
```

## 多容器 Pod

一个 Pod 可以包含多个容器，适合 Sidecar、Adapter、Ambassador 等紧密协作场景。下面示例使用 `writer` 容器持续生成页面文件，再由 `nginx` 容器通过共享目录对外提供访问。

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: multi-container-demo
  labels:
    app: multi-container-demo
spec:
  volumes:
    - name: shared-data
      emptyDir: {}

  containers:
    - name: writer
      image: busybox:1.36.1
      command:
        - /bin/sh
        - -c
        - |
          while true; do
            echo "Hello from writer container at $(date)" > /data/index.html
            sleep 5
          done
      volumeMounts:
        - name: shared-data
          mountPath: /data

    - name: nginx
      image: nginx:stable-alpine
      ports:
        - containerPort: 80
      volumeMounts:
        - name: shared-data
          mountPath: /usr/share/nginx/html
```

该 Pod 中包含两个容器：

| 容器 | 镜像 | 职责 |
| --- | --- | --- |
| `writer` | `busybox:1.36.1` | 每 5 秒向 `/data/index.html` 写入一段 HTML 内容 |
| `nginx` | `nginx:stable-alpine` | 将共享目录挂载为 Nginx 默认站点目录，对外提供 HTTP 访问 |

`spec.volumes` 定义了名为 `shared-data` 的 `emptyDir` 临时卷。`writer` 将该卷挂载到 `/data`，`nginx` 将同一个卷挂载到 `/usr/share/nginx/html`。两个容器虽然拥有各自独立的镜像和文件系统，但可以通过同一个 volume 交换文件。

本示例涉及的 volume 相关字段如下：

| 字段 | 说明 |
| --- | --- |
| `spec.volumes` | Pod 级别的卷定义，声明 Pod 内可被容器挂载的存储卷 |
| `spec.volumes[].name` | 卷名称，需要与容器中的 `volumeMounts[].name` 保持一致 |
| `spec.volumes[].emptyDir` | 临时卷类型，Pod 调度到节点后创建，Pod 删除后数据随之删除 |
| `spec.containers[].volumeMounts` | 容器级别的卷挂载配置，用于把 Pod 中定义的卷挂载到容器内 |
| `spec.containers[].volumeMounts[].mountPath` | 容器内的挂载路径，不同容器可以把同一个卷挂载到不同目录 |

创建并查看 Pod：

```bash
kubectl create -f multi-container-demo.yaml
kubectl get pod multi-container-demo -o wide
kubectl describe pod multi-container-demo
```

查看指定容器日志：

```bash
kubectl logs multi-container-demo -c writer
kubectl logs multi-container-demo -c nginx
```

进入 `nginx` 容器查看共享文件：

```bash
kubectl exec -it multi-container-demo -c nginx -- cat /usr/share/nginx/html/index.html
```

临时访问 Nginx：

```bash
kubectl port-forward pod/multi-container-demo 28080:80
curl http://127.0.0.1:28080
```

::: details 输出示例

```bash
$ kubectl get po multi-container-demo -owide
NAME                   READY   STATUS    RESTARTS   AGE   IP             NODE     NOMINATED NODE   READINESS GATES
multi-container-demo   2/2     Running   0          92s   10.244.75.74   work02   <none>           <none>

$ kubectl logs multi-container-demo -c writer

$ kubectl logs multi-container-demo -c nginx
/docker-entrypoint.sh: /docker-entrypoint.d/ is not empty, will attempt to perform configuration
/docker-entrypoint.sh: Looking for shell scripts in /docker-entrypoint.d/
/docker-entrypoint.sh: Launching /docker-entrypoint.d/10-listen-on-ipv6-by-default.sh
10-listen-on-ipv6-by-default.sh: info: Getting the checksum of /etc/nginx/conf.d/default.conf
10-listen-on-ipv6-by-default.sh: info: Enabled listen on IPv6 in /etc/nginx/conf.d/default.conf
/docker-entrypoint.sh: Sourcing /docker-entrypoint.d/15-local-resolvers.envsh
/docker-entrypoint.sh: Launching /docker-entrypoint.d/20-envsubst-on-templates.sh
/docker-entrypoint.sh: Launching /docker-entrypoint.d/30-tune-worker-processes.sh
/docker-entrypoint.sh: Configuration complete; ready for start up
2026/06/22 01:47:23 [notice] 1#1: using the "epoll" event method
2026/06/22 01:47:23 [notice] 1#1: nginx/1.30.3
2026/06/22 01:47:23 [notice] 1#1: built by gcc 15.2.0 (Alpine 15.2.0)
2026/06/22 01:47:23 [notice] 1#1: OS: Linux 6.8.0-124-generic
2026/06/22 01:47:23 [notice] 1#1: getrlimit(RLIMIT_NOFILE): 1024:524288
2026/06/22 01:47:23 [notice] 1#1: start worker processes
2026/06/22 01:47:23 [notice] 1#1: start worker process 30
2026/06/22 01:47:23 [notice] 1#1: start worker process 31

$ curl http://127.0.0.1:28080
Hello from writer container at Mon Jun 22 01:49:26 UTC 2026
```

:::

同一个 Pod 内的容器共享 Pod IP，可以通过 `localhost` 通信，也可以共享 volume。但每个容器仍然拥有独立的镜像、文件系统、环境变量和资源限制。多容器 Pod 适合强协作场景，如果两个服务需要独立扩缩容、独立发布或独立故障恢复，就应当拆分为不同的 Pod。

## 启动命令和参数

Pod 可以使用 `command` 和 `args` 覆盖镜像默认启动行为。`command` 用于指定容器入口命令，`args` 用于向入口命令传递参数。

| Kubernetes 字段 | Dockerfile 指令 | 作用 |
| --- | --- | --- |
| `command` | `ENTRYPOINT` | 覆盖容器入口命令 |
| `args` | `CMD` | 覆盖入口命令的默认参数 |

下面示例使用 `busybox` 启动一个循环脚本。`command` 指定入口命令为 `/bin/sh`，`args` 传入 `-c` 和需要执行的 shell 脚本：

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: command-args-demo
spec:
  containers:
    - name: busybox
      image: busybox:1.36.1
      command: ["/bin/sh"]
      args:
        - "-c"
        - "while true; do echo hello from command and args; date; sleep 5; done"
```

创建并查看 Pod：

```bash
kubectl create -f command-args-demo.yaml
kubectl get pod command-args-demo -o wide
```

查看容器输出：

```bash
kubectl logs command-args-demo
```

::: details 输出示例

```bash
$ kubectl get po command-args-demo -owide
NAME                READY   STATUS    RESTARTS   AGE   IP               NODE     NOMINATED NODE   READINESS GATES
command-args-demo   1/1     Running   0          55s   10.244.205.198   work01   <none>           <none>

$ kubectl logs command-args-demo
hello from command and args
Mon Jun 22 02:02:12 UTC 2026
hello from command and args
Mon Jun 22 02:02:17 UTC 2026
hello from command and args
Mon Jun 22 02:02:22 UTC 2026
hello from command and args
Mon Jun 22 02:02:27 UTC 2026
hello from command and args
Mon Jun 22 02:02:32 UTC 2026
hello from command and args
Mon Jun 22 02:02:37 UTC 2026
hello from command and args
Mon Jun 22 02:02:42 UTC 2026
hello from command and args
Mon Jun 22 02:02:47 UTC 2026
hello from command and args
Mon Jun 22 02:02:52 UTC 2026
```

:::

由于脚本中包含 `while true`，容器会持续运行并每 5 秒输出一次文本和时间。验证完成后可以删除 Pod：

```bash
kubectl delete pod -f command-args-demo.yaml
```

如果需要使用变量、循环或管道，应显式调用 `/bin/sh -c`。容器主进程退出后，容器随之退出，Pod 会根据 `restartPolicy` 决定后续处理方式。对于长期运行服务，启动命令应保持前台运行；如果命令执行结束，容器也会结束。
