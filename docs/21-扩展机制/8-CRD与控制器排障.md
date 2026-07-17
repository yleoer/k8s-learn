# CRD 与控制器排障

自定义资源出现问题时，先区分 API 注册失败、对象验证失败、控制器未运行、控制器无权限和外部依赖失败。直接修改 status 或手动删除受管资源只能用于受控诊断，控制器下一轮协调可能会重新创建或覆盖这些变更。

## 检查顺序

```bash
kubectl get crd crontabs.stable.example.com
kubectl api-resources --api-group=stable.example.com
kubectl get ct -A
kubectl describe ct sample -n team-a
kubectl get ev -n team-a --sort-by=.metadata.creationTimestamp
```

实际部署了控制器后，还应检查其 Pod 状态、日志、ServiceAccount、RoleBinding、leader election 以及针对自定义资源和受管资源的 `kubectl auth can-i` 结果。自定义资源 status 没有更新时，不能假定控制器已经成功协调。

> [!CAUTION]
> 删除 CRD 会删除该 CRD 的所有自定义资源。卸载控制器、删除 CR、清理外部资源和删除 CRD 必须是彼此独立且经过演练的步骤，尤其是控制器管理数据库或云资源时。

## 参考

- [自定义资源定义清理](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/#delete-a-customresourcedefinition)
