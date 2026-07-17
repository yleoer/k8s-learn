# ServiceAccount 与短期令牌

ServiceAccount 为集群内工作负载提供身份。Pod 指定 `serviceAccountName` 后，kubelet 会通过投射卷提供短期、可轮换的令牌；现代 Kubernetes 不会再为每个 ServiceAccount 自动创建长期 Token Secret。

应用应使用客户端库的 in-cluster 配置读取投射令牌和集群 CA，而不是把静态 Bearer Token 写入镜像、ConfigMap 或环境变量。

## 创建工作负载身份

```yaml [reporter-serviceaccount.yaml]
apiVersion: v1
kind: ServiceAccount
metadata:
  name: reporter
  namespace: team-a
automountServiceAccountToken: false
```

```bash
kubectl create -f reporter-serviceaccount.yaml
kubectl create token reporter -n team-a --duration=10m
```

`kubectl create token` 通过 TokenRequest API 获取短期令牌，适合受控调试或集成场景。令牌是凭据，命令输出不得写入终端历史、日志或版本库。

## 为 Pod 显式启用

```yaml{8-10} [reporter-pod.yaml]
apiVersion: v1
kind: Pod
metadata:
  name: reporter
  namespace: team-a
spec:
  serviceAccountName: reporter
  automountServiceAccountToken: true
  containers:
    - name: reporter
      image: curlimages/curl:8.21.0
      command: ["sh", "-c", "sleep 3600"]
```

ServiceAccount 上的 `automountServiceAccountToken: false` 是默认保护，Pod 级的显式 `true` 在此例中覆盖它。只为实际访问 API 的 Pod 启用挂载。

## 参考

- [ServiceAccount 使用场景](https://kubernetes.io/docs/concepts/security/service-accounts/#use-cases)
- [TokenRequest](https://kubernetes.io/docs/reference/kubernetes-api/authentication-resources/token-request-v1/)
