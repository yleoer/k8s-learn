# 用户凭据与 kubeconfig

普通用户身份由 Kubernetes 外部机制管理。生产环境通常使用 OIDC、受控证书签发或云身份集成，而不是在集群中保存用户名和密码。kubeconfig 可以保存多个集群、用户和 context，但文件可能包含令牌、私钥或客户端证书，应按凭据处理。

## 受控的证书请求

CertificateSigningRequest 可用于由集群签发客户端证书，但 CSR 的审批、签发、用户名和组映射属于安全敏感流程。不要把 CSR 当作无审批的自助注册接口；管理员需要验证请求来源、用途和过期策略。

```bash
kubectl get csr
kubectl describe csr <csr-name>
kubectl certificate approve <csr-name>
```

审批只允许签发流程继续，不应代替身份核验。kubeconfig 中的 context 仅选择集群、用户和命名空间，不提供额外授权。

> [!WARNING]
> 不要把带有 `client-key-data`、token 或 `exec` 凭据配置的 kubeconfig 提交到仓库，也不要从不受信任来源执行其中的 `exec` 插件。

## 参考

- [证书签名请求](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/)
- [使用 kubeconfig 文件组织集群访问](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)
