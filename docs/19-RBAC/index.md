# RBAC

调度与资源治理确定工作负载可以使用什么资源，访问控制决定谁可以读取或修改这些对象。Kubernetes 认证负责识别主体，RBAC 授权器根据 Role、Binding 和请求属性作出允许或拒绝决定。

本章记录人类用户、ServiceAccount、命名空间级与集群级授权，以及授权验证和排障。RBAC 不负责网络访问控制、Secret 加密或容器运行时隔离。

## 共同约定

权限清单应以 Git 管理并按主体、命名空间与用途拆分。优先创建小范围 Role 与 RoleBinding；只有确实需要集群范围资源时才创建 ClusterRole 或 ClusterRoleBinding。

## 参考

- [使用 RBAC 授权](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [ServiceAccount](https://kubernetes.io/docs/concepts/security/service-accounts/)
