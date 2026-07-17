# 模板与 Values

模板将 `.Values`、Release 元数据和 Chart 元数据转换为 YAML。模板必须保持渲染后的 YAML 缩进正确；不要用模板逻辑隐藏关键安全或资源配置，重要行为应在 values 中清晰可审计。

## Deployment 模板

下面是 `templates/deployment.yaml` 的完整示例，引用上一页的 `values.yaml`：

```yaml [templates/deployment.yaml]
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "web.fullname" . }}
  labels:
    {{- include "web.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "web.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "web.selectorLabels" . | nindent 8 }}
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: 80
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```

这个文件依赖 `helm create web` 生成的 `web.fullname`、`web.labels` 与 `web.selectorLabels` helpers。若不用生成的 helpers，就应在同一个 Chart 中提供等价且稳定的定义。

## 渲染检查

```bash
helm lint ./web
helm template web ./web --namespace team-a --values ./web/values.yaml
helm install web ./web --namespace team-a --create-namespace --dry-run --debug
```

`--dry-run --debug` 会联系 API Server 并显示渲染结果，可能受权限或集群策略影响；不应把输出中的 Secret 值复制到日志或文档。

## 参考

- [模板指南](https://helm.sh/docs/chart_template_guide/)
