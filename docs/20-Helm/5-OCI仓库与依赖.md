# OCI 仓库与依赖

Helm 支持将 Chart 作为 OCI artifact 推送、拉取和安装。OCI 引用需要使用 `oci://` 前缀，版本通过 `--version` 指定；凭据使用 `helm registry login` 管理，不应写入 Chart 或 values 文件。

## OCI 操作

```bash
helm registry login registry.example.com
helm package ./web
helm push web-0.1.0.tgz oci://registry.example.com/platform
helm pull oci://registry.example.com/platform/web --version 0.1.0
helm install web oci://registry.example.com/platform/web \
  --version 0.1.0 --namespace team-a --create-namespace
```

`registry.example.com` 是占位符，实际仓库地址、权限、TLS 证书和保留策略应由平台配置。Chart 包的名称和 `Chart.yaml` 中的 `name`、`version` 必须匹配。

## 依赖

```yaml [Chart.yaml]
apiVersion: v2
name: platform-app
version: 0.1.0
dependencies:
  - name: redis
    version: 20.6.3
    repository: oci://registry.example.com/platform-charts
    condition: redis.enabled
```

依赖版本必须固定；`helm dependency build ./platform-app` 依据 `Chart.lock` 下载可复现的依赖集合。示例仓库地址是占位符，不能直接执行，且不应因示例需要而把数据库凭据固化进父 Chart。

## 参考

- [使用 OCI 镜像仓库](https://helm.sh/docs/topics/registries/)
- [Chart 依赖](https://helm.sh/docs/topics/charts/#chart-dependencies)
