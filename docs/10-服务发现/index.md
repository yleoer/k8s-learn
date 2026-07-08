# 服务发现

第 09 章已记录 Deployment、StatefulSet 和 DaemonSet 等工作负载控制器。本章在工作负载稳定运行的基础上，进入 Pod 副本如何被其他应用稳定访问的记录阶段。

Kubernetes 中的 Pod 拥有独立 IP，但 Pod IP 不是稳定的服务入口。服务发现关注集群内服务间访问、集群外访问集群内服务，以及集群内访问外部依赖等几个访问边界。本章记录 Service、EndpointSlice、DNS、Headless Service、代理转发、Ingress、Gateway API、Traefik 和 ingress-nginx 附录等内容，为后续 NetworkPolicy 和微服务访问链路提供基础支撑。

## 服务边界

Pod 之间在集群网络内可以直接通信，但 Pod 会随着调度、重启、滚动更新和扩缩容不断变化。调用方如果直接维护 Pod IP，就会和工作负载生命周期强绑定。

常见流量方向可以粗略分为：

| 流量方向       | 常见资源                                      | 说明                                   |
|------------|-------------------------------------------|--------------------------------------|
| 集群内服务间访问   | Service                                   | Pod 访问同 Namespace 或其他 Namespace 中的服务 |
| 集群外访问集群内服务 | NodePort、LoadBalancer、Ingress、Gateway API | 对外暴露 Web、API 或其他业务入口                 |
| 集群内访问外部服务  | ExternalName、无 selector Service           | 使用 Kubernetes 资源统一管理外部依赖访问名称         |

Service 更偏向东西向访问和基础服务抽象。Ingress 更偏向 HTTP、HTTPS 等南北向流量入口；Gateway API 提供更细的网关与路由资源模型，Traefik 作为本章示例控制器承接 Ingress 和 Gateway API，ingress-nginx 退役后的存量记录放入本章附录。

## 标签选择

Label 是 Kubernetes 资源上的键值标记，用于描述资源身份、组件、版本、环境或其他分组信息。Pod、Deployment、Service、Node 等资源都可以设置 Label。

Selector 用于按 Label 筛选资源。Service 通过 `spec.selector` 匹配一组 Pod，Deployment 也通过 selector 管理自身创建的 Pod；因此标签规划是工作负载和服务发现共同依赖的基础。

下面示例使用 `app.kubernetes.io/name: MyApp` 作为 selector：

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  selector:
    app.kubernetes.io/name: MyApp
  ports:
    - protocol: TCP
      port: 80
      targetPort: 9376
```

该 Service 会匹配带有相同标签的 Pod。下面只是标签关系片段，不是完整 Pod 清单：

```yaml
metadata:
  labels:
    app.kubernetes.io/name: MyApp
```

Service 的 selector 是等值匹配。配置多个键值时，需要全部匹配才会纳入后端。生产中通常会使用稳定标签作为 Service selector，例如 `app.kubernetes.io/name`、`app.kubernetes.io/instance` 或团队内部约定的 `app`、`component`。

## 标签操作

`kubectl label` 用于更新资源标签，常见操作如下：

```bash
kubectl label pods foo unhealthy=true
kubectl label --overwrite pods foo status=unhealthy
kubectl label pods --all status=unhealthy
kubectl label -f pod.json status=unhealthy
kubectl label pods foo status=unhealthy --resource-version=1
kubectl label pods foo bar-
```

查看标签和按标签筛选资源时，可以结合 `kubectl get`：

```bash
kubectl get pods --show-labels
kubectl get pods -l app.kubernetes.io/name=MyApp
```

标签不仅用于 Service，也常用于 Deployment 管理 Pod、节点选择、资源筛选、监控采集和运维批量操作。Service selector 一旦规划不清晰，可能会把非目标 Pod 纳入流量，或者导致 Service 没有任何后端端点。

## 工作负载关系

Service 不直接管理 Pod 生命周期，只负责提供稳定访问入口和后端端点选择。Deployment、StatefulSet 等工作负载控制器负责创建和维护 Pod，Service 负责把这些 Pod 暴露给调用方。

典型关系如下：

```text
Deployment -> ReplicaSet -> Pod <- Service
```

Service 与 Deployment 之间没有所有者关系，二者通过 Pod 标签间接关联。因此修改 Deployment 名称不会自动影响 Service，修改 Pod 模板标签则可能直接影响 Service 后端。

下面以 `my-nginx` Deployment 说明这种关系：

```yaml [run-my-nginx.yaml]
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-nginx
spec:
  selector:
    matchLabels:
      run: my-nginx
  replicas: 2
  template:
    metadata:
      labels:
        run: my-nginx
    spec:
      containers:
        - name: my-nginx
          image: nginx
          ports:
            - containerPort: 80
```

对应 Service 使用 `run: my-nginx` 选择后端 Pod：

```yaml [nginx-svc.yaml]
apiVersion: v1
kind: Service
metadata:
  name: my-nginx
  labels:
    run: my-nginx
spec:
  ports:
    - port: 80
      protocol: TCP
  selector:
    run: my-nginx
```

该 Service 未显式设置 `spec.type`，因此类型默认为 `ClusterIP`。`targetPort` 未配置时，默认等于 `port`。

## 参考

本章背景内容参考以下 Kubernetes 英文文档、kubectl 参考和示例文件：

- [Service](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Connecting Applications with Services](https://kubernetes.io/docs/tutorials/services/connect-applications-service/)
- [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Ingress API reference](https://kubernetes.io/docs/reference/kubernetes-api/networking/ingress-v1/)
- [IngressClass API reference](https://kubernetes.io/docs/reference/kubernetes-api/networking/ingressclass-v1/)
- [kubectl label](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_label/)
- [run-my-nginx.yaml](https://raw.githubusercontent.com/kubernetes/website/main/content/en/examples/service/networking/run-my-nginx.yaml)
- [nginx-svc.yaml](https://raw.githubusercontent.com/kubernetes/website/main/content/en/examples/service/networking/nginx-svc.yaml)
