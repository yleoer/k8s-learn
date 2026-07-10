# 静态 Pod

静态 Pod 由节点上的 kubelet 直接管理，不经过 kube-scheduler 调度，API server 也无法控制它的生命周期。kubelet 监视静态 Pod 的清单来源，Pod 失败时负责重启。第 01 章 kubeadm 部署的 kube-apiserver、kube-controller-manager、kube-scheduler 和 etcd，就是以静态 Pod 形式运行在控制面节点上的。

## 定义与边界

静态 Pod 始终绑定到某一个节点的 kubelet：

- 清单文件放在节点本地，由 kubelet 直接读取并创建 Pod，创建过程不依赖 API server。这也是控制面组件能够以 Pod 形式自举的原因——kubelet 可以在 API server 可用之前先把它拉起来。
- 控制器、调度器和 `kubectl delete` 都无法真正删除静态 Pod，删除清单文件才能移除它。
- 集群级的节点代理类组件不建议用静态 Pod 维护，应优先使用 DaemonSet，由控制面统一管理。

## 配置方式

静态 Pod 的清单目录由 kubelet 配置文件中的 `staticPodPath` 字段指定。kubelet 默认不启用该字段（默认值为空字符串），kubeadm 部署时会将其设置为 `/etc/kubernetes/manifests`。下面只展示相关字段，不是完整的 `KubeletConfiguration`：

```yaml{3}
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
staticPodPath: /etc/kubernetes/manifests
```

该片段只说明字段位置，不应直接覆盖现有节点配置。`staticPodPath` 也可以指向单个静态 Pod 清单文件；命令行参数 `--pod-manifest-path` 是等价但已弃用的配置方式，另有 `staticPodURL` 支持从 HTTP 地址获取清单。

kubelet 会周期性扫描该目录，处理其中所有不以点号开头的文件，文件的增删会同步为静态 Pod 的创建和删除。

> [!CAUTION]
> kubelet 不按扩展名过滤清单文件。在清单目录中保留 `kube-apiserver.yaml.backup` 这类备份文件，会被当作又一份同名 Pod 的清单处理，行为不可预期。备份应放到目录之外，或使用点号开头的文件名。

## 镜像 Pod

kubelet 会为每个静态 Pod 在 API server 上创建一个对应的镜像 Pod（mirror Pod），让静态 Pod 在 `kubectl` 中可见。镜像 Pod 只是投影：

- Pod 名称会自动追加连字符和节点主机名后缀，例如 `kube-apiserver-master01`。
- 通过 `kubectl delete` 删除镜像 Pod，静态 Pod 本身不受影响，kubelet 会立刻重建镜像 Pod。
- 镜像 Pod 带有 `kubernetes.io/config.mirror` 注解，可以据此识别。

在 kubeadm 集群中验证这组行为：

```bash
ls /etc/kubernetes/manifests
kubectl get pods -n kube-system -o wide | grep "$(hostname)"
kubectl delete pod -n kube-system kube-scheduler-<node-name>
kubectl get pods -n kube-system | grep kube-scheduler
```

删除镜像 Pod 后，短暂间隔内会重新出现同名 Pod，而节点上的调度器进程并未重启——被删除又重建的只是 API server 中的投影对象。

## 限制

静态 Pod 的 spec 不能引用其他 API 对象，也缺少一部分常规 Pod 能力：

- 不能引用 ServiceAccount、ConfigMap、Secret 等资源，配置只能通过镜像、hostPath 挂载或命令行参数注入。
- 不支持临时容器，`kubectl debug` 的临时容器方式对静态 Pod 无效，排障需要回到节点上使用 `crictl` 或 `kubectl debug node/`。
- 不受控制器管理，没有滚动更新语义；修改清单文件后，kubelet 会按新清单重建 Pod。

## 参考

- [Static Pods](https://kubernetes.io/docs/concepts/workloads/pods/static-pods/)
- [Create static Pods](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/)
- [Kubelet Configuration v1beta1](https://kubernetes.io/docs/reference/config-api/kubelet-config.v1beta1/)
