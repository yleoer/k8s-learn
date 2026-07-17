# CRD 与自定义资源

CustomResourceDefinition 使用 `apiextensions.k8s.io/v1` 注册新的 API 资源。CRD 注册 API 的存储、发现与基础验证；它本身不会创建或维护外部工作负载，只有控制器才能把 `spec` 转化为实际行为。

## 创建一个命名空间资源

```yaml [crontab-crd.yaml]
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: crontabs.stable.example.com
spec:
  group: stable.example.com
  scope: Namespaced
  names:
    plural: crontabs
    singular: crontab
    kind: CronTab
    shortNames:
      - ct
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              required:
                - cronSpec
                - image
              properties:
                cronSpec:
                  type: string
                  minLength: 1
                image:
                  type: string
                  minLength: 1
                replicas:
                  type: integer
                  minimum: 1
            status:
              type: object
              properties:
                observedGeneration:
                  type: integer
                phase:
                  type: string
        subresources:
          status: {}
---
apiVersion: stable.example.com/v1
kind: CronTab
metadata:
  name: sample
  namespace: team-a
spec:
  cronSpec: "*/5 * * * *"
  image: nginx:1.31-alpine
  replicas: 1
```

```bash
kubectl create ns team-a
kubectl create -f crontab-crd.yaml
kubectl get crd crontabs.stable.example.com
kubectl get ct -n team-a
```

该文件完整注册 CRD 并创建一个自定义资源。由于本章没有部署控制器，`CronTab` 仅被 API Server 存储和验证，不会自动创建任何 CronJob、Pod 或 Deployment。

## 参考

- [自定义资源定义](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/)
