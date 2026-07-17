# CRD 版本演进

CRD 可以同时服务多个版本，但每个对象只有一个存储版本。`served: true` 决定 API Server 是否提供该版本，`storage: true` 指定写入 etcd 的版本；同一 CRD 只能有一个存储版本。

新增字段通常比重命名、改变类型或改变默认语义更容易兼容。升级前应定义旧对象读取、新对象写入、转换、回滚和存储迁移路径，并在生产数据副本上验证。

## 转换边界

同一存储版本的多个 API 版本可以通过 `None` 转换处理字段等价的情况；语义或字段结构不同的版本需要 conversion webhook。webhook 是 API 请求路径的一部分，必须具备高可用、超时、证书轮换和兼容性测试，不能将业务副作用放入转换逻辑。

废弃版本时，先停止让客户端写入旧版本，再完成对象存储迁移和消费者升级，最后设置 `served: false`。删除某个版本前应确认不再有客户端、备份或 Git 清单引用它。

> [!WARNING]
> CRD 版本变更会影响 API 客户端、控制器、Git 清单、备份和灾难恢复。不要通过直接编辑 etcd 或删除重建 CRD 来“迁移”生产数据。

## 存储版本检查

复用[CRD 与自定义资源](./2-CRD与自定义资源.md#创建一个命名空间资源)中的 `crontab-crd.yaml` 后，可以直接观察 API Server 记录的服务版本与存储版本：

```bash
kubectl get crd crontabs.stable.example.com \
  -o jsonpath='{range .spec.versions[*]}{.name}{" served="}{.served}{" storage="}{.storage}{"\n"}{end}'
kubectl get crd crontabs.stable.example.com \
  -o jsonpath='{.status.storedVersions}{"\n"}'
```

输出中只有一个 `storage=true`；`status.storedVersions` 表示 etcd 中仍可能存在对象的版本集合。为新版本切换 storage 前，应先在备份副本和升级后的控制器上验证读取、写入与转换，再处理旧版本客户端。

## 参考

- [自定义资源定义中的版本](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definition-versioning/)
