# 资源配额

节点级 requests 和 limits 解决单个 Pod 的资源声明，而多团队共享集群还需要命名空间级上限。ResourceQuota 在 API 请求准入时统计并限制该命名空间的累计用量。

本章记录计算、存储和对象计数配额，以及按环境和租户组织命名空间的边界。LimitRange 补充单个对象默认值和范围，QoS 则由实际资源配置决定。

## 共同约定

配额只约束一个命名空间，不能预留节点容量，也不能替代容量规划。配额对象应由平台管理员管理，租户账户不应具有修改或删除其所在命名空间配额的权限。

## 参考

- [资源配额](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- [ResourceQuota API 参考](https://kubernetes.io/docs/reference/kubernetes-api/policy-resources/resource-quota-v1/)
