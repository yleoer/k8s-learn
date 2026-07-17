# 限制范围

ResourceQuota 控制命名空间总用量，仍不能防止一个容器使用过大的请求或遗漏资源声明。LimitRange 通过准入控制为单个容器、Pod、PVC 或存储请求设置最小值、最大值和默认值。

本章记录 LimitRange 的对象类型、默认资源和与 ResourceQuota 的配合。它不保证节点上有可用资源，也不改变调度器的容量判断。

## 共同约定

每个有计算资源配额的命名空间应在授予工作负载创建权限前配置 LimitRange。默认值是平台约定，变更会影响后续创建的对象，应通过版本化清单和变更记录管理。

## 参考

- [LimitRange](https://kubernetes.io/docs/concepts/policy/limit-range/)
