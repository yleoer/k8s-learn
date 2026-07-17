# 污点容忍

节点选择和亲和性表达 Pod 希望去哪里，污点则表达节点拒绝哪些 Pod。两者组合后，节点池既能按能力分类，也能保留给明确获准的工作负载。

本章记录污点效果、容忍匹配、维护与故障处理，以及专用节点的隔离模式。它不替代 RBAC、NetworkPolicy 或操作系统级安全隔离。

## 共同约定

污点键应使用域名式前缀，例如 `dedicated.example.com/team-a`。允许进入专用节点的工作负载同时应设置节点亲和性，避免“有容忍但没有选择”造成的非预期落点。

## 参考

- [污点与容忍](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
- [kubectl taint 命令](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_taint/)
