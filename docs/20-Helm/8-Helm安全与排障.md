# Helm 安全与排障

Helm 失败可能发生在模板渲染、API 授权、准入、资源创建或工作负载就绪任一阶段。Release 显示为成功只说明 Helm 的操作完成，仍需要查看 Kubernetes 对象状态和事件。

## 检查命令

```bash
helm list -n team-a
helm status web -n team-a
helm get manifest web -n team-a
helm get values web -n team-a --all
kubectl get all -n team-a -l app.kubernetes.io/instance=web
kubectl get ev -n team-a --sort-by=.metadata.creationTimestamp
```

`helm get values` 和渲染输出可能包含敏感值。生产 Chart 应使用外部密钥系统或受控 Secret 引用，并避免用 `--set` 在命令行传递凭据，因为命令行通常会进入历史和审计日志。

> [!CAUTION]
> 不要用 `--force` 或宽泛的 `--disable-openapi-validation` 解决常规升级失败。先确认 API 兼容性、不可变字段、CRD 生命周期和资源所有权；强制替换可能造成短暂中断或删除重建。

## 参考

- [Helm 安全模型](https://helm.sh/docs/topics/security/)
- [helm status 命令](https://helm.sh/docs/helm/helm_status/)
