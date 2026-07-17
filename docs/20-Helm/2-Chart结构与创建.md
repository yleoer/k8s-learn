# Chart 结构与创建

`helm create web` 生成可修改的 Chart 骨架。Chart 元数据位于 `Chart.yaml`，部署参数位于 `values.yaml`，资源模板位于 `templates/`；`templates/_helpers.tpl` 通常保存可复用命名模板，`templates/NOTES.txt` 保存安装后的提示文本。

## 最小元数据

```yaml [Chart.yaml]
apiVersion: v2
name: web
description: A versioned web workload chart
type: application
version: 0.1.0
appVersion: "1.31.0"
```

`version` 是 Chart 包版本，变更模板、默认值或依赖时应递增；`appVersion` 是展示用的应用版本元数据，不会自动设置容器镜像 tag。

## 参数文件

```yaml [values.yaml]
replicaCount: 2

image:
  repository: nginx
  tag: 1.31-alpine
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi
```

可通过以下命令创建目录并检查 Chart；未给出完整模板的局部片段仅用于解释字段关系，不能直接作为部署清单。

```bash
helm create web
helm lint ./web
helm show chart ./web
```

## 参考

- [Chart 文件结构](https://helm.sh/docs/topics/charts/#the-chart-file-structure)
- [Chart.yaml 文件](https://helm.sh/docs/topics/charts/#the-chartyaml-file)
