# Pod 亲和与反亲和

Pod 亲和性依据其他 Pod 的标签和拓扑域决定落点：亲和性倾向共置，反亲和性倾向分散。它解决“与谁在一起或分开”的问题，不替代 Service、网络策略或存储拓扑。

`requiredDuringSchedulingIgnoredDuringExecution` 的 Pod 反亲和性适合少量关键副本，但调度器需要在节点和拓扑域中检查已有 Pod，集群规模较大时成本明显。大规模均衡副本通常优先采用拓扑分布约束。

## 必须分散的副本

下面的 Deployment 要求同一应用的副本不能位于同一主机。`topologyKey: kubernetes.io/hostname` 将每台主机视为一个拓扑域。

```yaml [api-anti-affinity.yaml]
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  replicas: 3
  selector:
    matchLabels:
      app.kubernetes.io/name: api
  template:
    metadata:
      labels:
        app.kubernetes.io/name: api
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchLabels:
                  app.kubernetes.io/name: api
              topologyKey: kubernetes.io/hostname
      containers:
        - name: api
          image: nginx:1.31-alpine
          ports:
            - containerPort: 80
```

```bash
kubectl create -f api-anti-affinity.yaml
kubectl get po -l app.kubernetes.io/name=api -o wide
```

若可用主机少于副本数，超出的副本会停在 `Pending`。这是硬约束的预期结果；不应为消除 Pending 而降低为软规则，除非可用性目标允许共置。

## 尽量共置的缓存访问

下面片段仅说明字段关系，并不是完整资源。它让 API Pod 倾向与 `role=cache` 的 Pod 位于同一可用区：

```yaml{2-10}
affinity:
  podAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 50
        podAffinityTerm:
          labelSelector:
            matchLabels:
              role: cache
          topologyKey: topology.kubernetes.io/zone
```

共置可能缩短网络路径，但也会放大可用区故障的影响。缓存和计算是否共置应由延迟、容量和故障域目标共同决定。

## 命名空间范围

未指定 `namespaces` 或 `namespaceSelector` 时，Pod 亲和性仅匹配与待调度 Pod 相同命名空间的 Pod。跨命名空间选择会扩大调度依赖面，且 ResourceQuota 可用 `CrossNamespacePodAffinity` scope 对此类 Pod 施加限制。

## 参考

- [Pod 亲和性与反亲和性](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#inter-pod-affinity-and-anti-affinity)
- [配额范围](https://kubernetes.io/docs/concepts/policy/resource-quotas/#quota-scopes)
