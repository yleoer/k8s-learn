# LimitRange 资源

LimitRange 在命名空间内由 LimitRanger 准入控制器执行。它可以对 `Container`、`Pod`、`PersistentVolumeClaim` 等类型声明 `min`、`max`、`default`、`defaultRequest` 与 `maxLimitRequestRatio`。

## 容器默认值与范围

```yaml [team-a-limits.yaml]
apiVersion: v1
kind: LimitRange
metadata:
  name: team-a-limits
  namespace: team-a
spec:
  limits:
    - type: Container
      min:
        cpu: 50m
        memory: 64Mi
      max:
        cpu: "2"
        memory: 2Gi
      defaultRequest:
        cpu: 100m
        memory: 128Mi
      default:
        cpu: "1"
        memory: 512Mi
      maxLimitRequestRatio:
        cpu: "10"
        memory: "4"
```

```bash
kubectl create -f team-a-limits.yaml
kubectl describe limitrange team-a-limits -n team-a
```

缺少 requests 或 limits 的容器会在创建时得到默认值；超过 `max`、低于 `min` 或违反最大 limit/request 比例的对象会被拒绝。默认值只在对象创建时注入，修改 LimitRange 不会回写已有 Pod。

## 参考

- [LimitRange 约束](https://kubernetes.io/docs/concepts/policy/limit-range/#constraints)
