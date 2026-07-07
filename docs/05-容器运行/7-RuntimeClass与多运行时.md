# RuntimeClass 与多运行时

本章前文的容器都由 runc 运行：共享宿主机内核，靠 namespaces 和 cgroups 隔离。多租户、运行不可信代码或强合规场景需要更强的隔离边界，Kata Containers 和 gVisor 提供了两种代表性方案。RuntimeClass 是 Kubernetes 在这类场景下按 Pod 选择容器运行时的机制。

## RuntimeClass 资源

RuntimeClass 是集群级资源，属于 `node.k8s.io/v1`，自 Kubernetes v1.20 起为稳定特性。它的结构很小：没有 `spec`，核心字段是顶层的 `handler`，指向 CRI 运行时配置中的处理器名称：

```yaml [runtimeclass-gvisor.yaml]
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
```

`handler` 必须是小写 DNS 标签格式，创建后不可修改。Pod 通过 `spec.runtimeClassName` 引用：

```yaml [gvisor-pod.yaml]
apiVersion: v1
kind: Pod
metadata:
  name: nginx-gvisor
spec:
  runtimeClassName: gvisor
  containers:
    - name: nginx
      image: nginx:1.31-alpine
```

不设置 `runtimeClassName` 时，Pod 使用 CRI 配置的默认运行时，containerd 的出厂默认是 runc。引用的 RuntimeClass 不存在，或者 CRI 无法运行对应 handler 时，Pod 会直接进入 Failed 终态而不是 Pending，排障时应查看 Pod 事件。

## handler 与 containerd 配置

`handler` 的值对应 containerd 配置中 runtimes 表的键名。注册一个新运行时需要在 `/etc/containerd/config.toml` 中添加对应段落，配置路径随 containerd 大版本不同：

```toml [containerd 2.x]
[plugins.'io.containerd.cri.v1.runtime'.containerd]
  default_runtime_name = "runc"

  [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.gvisor]
    runtime_type = "io.containerd.runsc.v1"

  [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.kata]
    runtime_type = "io.containerd.kata.v2"
```

```toml [containerd 1.x]
[plugins."io.containerd.grpc.v1.cri".containerd]
  default_runtime_name = "runc"

  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.gvisor]
    runtime_type = "io.containerd.runsc.v1"

  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata]
    runtime_type = "io.containerd.kata.v2"
```

修改后重启 containerd 生效。`runtime_type` 中的 `io.containerd.<name>.v2` 会被翻译为 shim 二进制名 `containerd-shim-<name>-v2`，例如 Kata 的 shim 是 `containerd-shim-kata-v2`，gVisor 的是 `containerd-shim-runsc-v1`，这些二进制需要预先安装在节点 PATH 中。

## scheduling 与 overhead

RuntimeClass 还有两个可选字段，解决“Pod 只能调度到装了对应运行时的节点”和“沙箱自身消耗资源”两个问题：

- `scheduling`（自 v1.16 起为 Beta）：`nodeSelector` 在准入时与 Pod 自身的 nodeSelector 合并取交集，冲突时 Pod 被拒绝；`tolerations` 合并取并集。运行时只安装在部分节点时，应配合节点标签使用。
- `overhead`（自 v1.24 起为稳定特性）：声明该运行时每个 Pod 的固定开销，调度器按“容器 requests 之和加 overhead”选择节点，kubelet 据此设置 Pod cgroup 上限，ResourceQuota 也会计入。

```yaml [runtimeclass-kata-fc.yaml]
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: kata-fc
handler: kata-fc
overhead:
  podFixed:
    memory: 120Mi
    cpu: 250m
scheduling:
  nodeSelector:
    katacontainers.io/kata-runtime: "true"
```

overhead 由 RuntimeClass 在准入时注入 Pod，Pod 自行设置 `spec.overhead` 会被拒绝。注入结果可以通过 `kubectl get pod <pod-name> -o jsonpath='{.spec.overhead}'` 验证。

## Kata Containers

Kata Containers 为每个 Pod 启动一个轻量虚拟机，容器运行在独立的 guest 内核中，以硬件虚拟化换取接近虚拟机的隔离强度。

- 宿主机要求：CPU 支持硬件虚拟化（Intel VT-x、AMD SVM），云主机需要开启嵌套虚拟化或使用裸金属节点，可用 `kata-runtime check` 检测。
- 安装方式：官方推荐 kata-deploy Helm chart，它以 DaemonSet 形式向节点分发运行时并按 hypervisor 创建 `kata-qemu`、`kata-clh`、`kata-fc`、`kata-dragonball` 等 RuntimeClass；聚合名 `kata` 的 RuntimeClass 默认不创建。
- hypervisor 选择：QEMU 兼容性和机密计算支持最好，Cloud Hypervisor 与 Firecracker 更轻量，Dragonball 与 Rust 版运行时集成。
- 主要限制：不支持 `hostNetwork`，不支持 `volumeMounts.subPath`；`privileged` 语义与 runc 不同，只在 guest 内提权，containerd 侧建议配置 `privileged_without_host_devices = true` 避免宿主机设备透传进虚拟机；每个 Pod 有固定的虚拟机内存开销，kata-deploy 当前默认按 hypervisor 声明约 130Mi（Cloud Hypervisor、Firecracker、Dragonball）到 320Mi（QEMU），应通过 overhead 声明而不是省略。

## gVisor

gVisor 用另一条路径实现隔离：在用户态实现一个 Linux 兼容的应用内核 Sentry，拦截并自行处理容器的系统调用，不把系统调用透传给宿主内核；文件访问由独立的 Gofer 进程代理。它的 OCI 运行时是 runsc。

- 平台机制：systrap 是当前默认平台，适用于虚拟机和物理机；KVM 平台在裸金属上性能更好；ptrace 平台已不再受支持。
- 资源模型：没有固定的虚拟机开销，内存随应用弹性使用，启动接近普通容器。
- 主要限制：未实现全部系统调用和 `/proc`、`/sys` 文件，部分软件不兼容；系统调用密集型负载性能下降明显；GPU 需要 nvproxy 且只支持特定 NVIDIA 驱动版本。
- gVisor 官方文档给出的 RuntimeClass 示例即前文的 `name: gvisor`、`handler: runsc`。

## 选型对比

| 维度 | runc | Kata Containers | gVisor |
| --- | --- | --- | --- |
| 隔离机制 | namespaces + cgroups，共享宿主内核 | 轻量虚拟机，独立 guest 内核 | 用户态应用内核拦截系统调用 |
| 启动与内存开销 | 最低 | 每 Pod 固定虚拟机开销，启动较慢 | 启动快，内存弹性，固定开销低 |
| 兼容性 | 完整 | 好，但 hostNetwork、subPath 等受限 | 部分系统调用与 /proc 缺失 |
| 性能特征 | 基线 | 计算型接近原生，I/O 路径变长 | 系统调用密集型负载明显变慢 |
| 典型场景 | 默认选择 | 多租户强隔离、机密计算 | 运行不可信代码、SaaS 沙箱 |

多数集群的合理形态是：默认 runc，为少量需要强隔离的 Namespace 或工作负载单独提供 Kata 或 gVisor 的 RuntimeClass，并用 `scheduling` 把它们约束到安装了对应运行时的节点池。

## 记录要点

- RuntimeClass 是集群级资源，建议通过 RBAC 限制写权限，避免业务侧随意指向未经评估的运行时。
- handler 与 containerd 配置键名必须一致，节点上还要有对应 shim 二进制，三者缺一个 Pod 就会 Failed。
- 沙箱运行时的固定开销应写入 overhead，否则节点会被过量装箱。
- Kata 与 gVisor 的限制都体现在与宿主机深度交互的能力上，迁移前先核对 hostNetwork、特权容器、设备挂载和性能敏感路径。

## 参考

- [Runtime Class](https://kubernetes.io/docs/concepts/containers/runtime-class/)
- [Pod Overhead](https://kubernetes.io/docs/concepts/scheduling-eviction/pod-overhead/)
- [containerd CRI config](https://github.com/containerd/containerd/blob/main/docs/cri/config.md)
- [Kata Containers](https://github.com/kata-containers/kata-containers)
- [Kata Containers Limitations](https://github.com/kata-containers/kata-containers/blob/main/docs/Limitations.md)
- [gVisor Documentation](https://gvisor.dev/docs/)
- [gVisor Platforms](https://gvisor.dev/docs/architecture_guide/platforms/)
