# 验证集群与常见排障

本文通过部署一个 nginx 测试应用，对集群调度、Pod 网络、Service 转发和资源指标 API 进行端到端验证，并汇总初始化阶段常见的排障命令与处理思路。

## 部署测试应用

```bash
kubectl create deployment sample-nginx --image=nginx:1.27
kubectl expose deployment sample-nginx --port=80 --type=NodePort
```

查看部署状态：

```bash
kubectl get deploy,pod,svc -l app=sample-nginx -o wide
```

::: details 输入类似如下

```bash
$ kubectl get deploy,pod,svc -l app=sample-nginx -o wide
NAME                           READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS   IMAGES       SELECTOR
deployment.apps/sample-nginx   1/1     1            1           43s   nginx        nginx:1.27   app=sample-nginx

NAME                               READY   STATUS    RESTARTS   AGE   IP               NODE     NOMINATED NODE   READINESS GATES
pod/sample-nginx-b86898df9-wmf9n   1/1     Running   0          43s   10.244.205.249   work01   <none>           <none>

NAME                   TYPE       CLUSTER-IP       EXTERNAL-IP   PORT(S)        AGE   SELECTOR
service/sample-nginx   NodePort   10.100.223.204   <none>        80:31460/TCP   17s   app=sample-nginx
```

:::

确认以下几点后，继续执行访问验证：
- Deployment 的期望副本数已就绪 `1/1`
- Pod 状态为 `Running`
- Service 类型为 `NodePort` 且已分配 `30000-32767` 范围内的端口。

## 访问验证

获取 NodePort，并通过已配置解析的节点主机名访问：

```bash
NODE_PORT=$(kubectl get svc sample-nginx -o jsonpath='{.spec.ports[0].nodePort}')
curl "http://master:${NODE_PORT}"
```

这里的 `master` 来自前文 `/etc/hosts` 中配置的静态解析。NodePort 通常可以通过任意可达节点地址访问，也可以替换为 `work01`、`work02` 或节点 IP；若从集群外部访问，应确认访问端所在环境能够解析该主机名，并确认节点防火墙、云安全组或上层网络 ACL 已放行对应 NodePort。

也可从集群内部创建临时 curl Pod 验证 Service 转发。DNS 名称规则为 `<service>.<namespace>.svc.cluster.local`，默认 namespace 下的 Service 可省略 `<namespace>.svc.cluster.local`：

```bash
kubectl run sample-curl --rm -i --restart=Never \
  --image=curlimages/curl:8.10.1 \
  -- curl -I --max-time 10 http://sample-nginx.default.svc.cluster.local
```

::: details 结果类似如下

```bash
$ kubectl run sample-curl --rm -i --restart=Never \
  --image=curlimages/curl:8.10.1 \
  -- curl -I --max-time 10 http://sample-nginx.default.svc.cluster.local
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
All commands and output from this session will be recorded in container logs, including credentials and sensitive information passed through thecommand prompt.
If you don't see a command prompt, try pressing enter.
  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0HTTP/1.1 200 OK
  0   615    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
Server: nginx/1.27.5
Date: Fri, 03 Jul 2026 02:57:09 GMT
Content-Type: text/html
Content-Length: 615
Last-Modified: Wed, 16 Apr 2025 12:01:11 GMT
Connection: keep-alive
ETag: "67ff9c07-267"
Accept-Ranges: bytes

pod "sample-curl" deleted from default namespace
```
:::

验证完成后清理测试资源：

```bash
kubectl delete svc sample-nginx
kubectl delete deployment sample-nginx
```

## 指标验证

Metrics Server 正常运行后，`metrics.k8s.io` APIService 应处于可用状态：

```bash
kubectl get apiservice v1beta1.metrics.k8s.io
```

查看节点和 Pod 的实时 CPU、内存使用量：

```bash
kubectl top nodes
kubectl top pods -A
```
::: details 结果类似如下

```bash
$ kubectl get apiservice v1beta1.metrics.k8s.io
NAME                     SERVICE                      AVAILABLE   AGE
v1beta1.metrics.k8s.io   kube-system/metrics-server   True        7d

$ kubectl top nodes
NAME     CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
master   146m         7%       2350Mi          62%
work01   47m          2%       1100Mi          29%
work02   30m          1%       1038Mi          27%

$ kubectl top pods -A
NAMESPACE          NAME                                       CPU(cores)   MEMORY(bytes)
calico-apiserver   calico-apiserver-5b89d6564d-6qgwv          2m           38Mi
calico-apiserver   calico-apiserver-5b89d6564d-bkw8x          3m           109Mi
calico-system      calico-kube-controllers-75f665b4f6-gmcq9   2m           76Mi
calico-system      calico-node-6xv5x                          19m          251Mi
calico-system      calico-node-8m5m6                          22m          247Mi
calico-system      calico-node-t4mxk                          27m          250Mi
calico-system      calico-typha-7f8ffbb8-bjdrk                3m           59Mi
calico-system      calico-typha-7f8ffbb8-ssnhh                4m           62Mi
calico-system      csi-node-driver-jtn4l                      1m           35Mi
calico-system      csi-node-driver-kh22j                      1m           35Mi
calico-system      csi-node-driver-tqs2z                      1m           34Mi
kube-system        coredns-589f44dc88-g44wq                   4m           13Mi
kube-system        coredns-589f44dc88-rskr5                   3m           66Mi
kube-system        etcd-master                                36m          89Mi
kube-system        kube-apiserver-master                      67m          453Mi
kube-system        kube-controller-manager-master             18m          121Mi
kube-system        kube-proxy-qqjkm                           1m           55Mi
kube-system        kube-proxy-qr8gw                           2m           56Mi
kube-system        kube-proxy-qzxnt                           2m           55Mi
kube-system        kube-scheduler-master                      10m          64Mi
kube-system        metrics-server-564b7c8ccc-kfz5r            5m           71Mi
tigera-operator    tigera-operator-579877d476-xz84d           4m           136Mi
```

:::

## 常见排障

### Node NotReady 排查

节点长时间处于 `NotReady` 状态时，按以下顺序排查：

```bash
# 查看节点状态与条件
kubectl describe node <node-name> | grep -A 5 Conditions

# 确认 kubelet 运行状态
ssh <node-ip> "sudo systemctl status kubelet --no-pager"

# 查看 kubelet 日志，关注 CSR、网络和运行时错误
ssh <node-ip> "sudo journalctl -u kubelet --no-pager --since '5 min ago' | tail -80"

# 确认 containerd 是否正常
ssh <node-ip> "sudo systemctl status containerd --no-pager && sudo crictl ps"
```

常见原因包括：
- kubelet 未启动或与 containerd 通信异常（确认 `--cri-socket` 路径正确）。
- CNI 网络插件未安装或异常。
- 节点 swap 未彻底关闭。
- 节点时间偏差过大，证书校验失败。

### CoreDNS CrashLoopBackOff

CoreDNS 持续重启时，先查看日志：

```bash
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=50
```

常见原因：
- **Pod 网络不通**：CNI 插件安装后 CoreDNS Pod 未获得有效 IP，重启 Pod 可恢复。
- **ConfigMap 配置错误**：检查 `kubectl describe cm coredns -n kube-system` 中的 Corefile 语法。
- **节点 DNS 解析问题**：CoreDNS 依赖节点上的 DNS 解析上行 /etc/resolv.conf，如果宿主机 resolv.conf 配置异常（例如 nameserver 不可达、search 域过长），CoreDNS 启动时无法完成自身解析。

### kubelet 无法启动

```bash
sudo systemctl status kubelet --no-pager
sudo journalctl -u kubelet --no-pager --since '10 min ago' | tail -100
```

常见原因：
- cgroup driver 不匹配：kubelet 默认使用 `systemd`，containerd 配置中 `SystemdCgroup` 必须为 `true`。
- 静态 Pod 清单语法错误：检查 `/etc/kubernetes/manifests/` 目录下的 YAML 文件。
- 已锁定版本与仓库源版本不一致：用 `kubelet --version` 确认已安装版本，与 APT 源是否匹配。

### 重置实验集群

> [!CAUTION]
> **生产环境请勿操作**

若需在实验环境中彻底重建集群，可在相关节点上依次执行以下命令：

```bash
sudo kubeadm reset
sudo rm -rf /etc/cni/net.d
sudo rm -rf "$HOME/.kube"
sudo systemctl restart containerd
```

该操作将清除当前节点上的 Kubernetes 配置及部分网络状态，但不会自动清理 kube-proxy 写入主机的 iptables、nftables 或 IPVS 规则。若需要彻底复原实验节点，应按当前网络模式额外清理相关规则，执行前请确认操作对象正确。

执行 `kubeadm reset` 前可先记录当前 kube-proxy 使用的镜像和代理模式：

```bash
kubectl -n kube-system get daemonset kube-proxy -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl -n kube-system get configmap kube-proxy -o jsonpath='{.data.config\.conf}' | grep '^mode:'
```

完成 `kubeadm reset` 且原 kube-proxy 不再运行后，在每个需要清理的 Linux 节点上，使用与集群一致的 kube-proxy 镜像执行 `--cleanup`。以下版本号应替换为当前集群实际使用的 kube-proxy 版本。

使用 Docker 启动 kube-proxy 容器（需要节点上安装有 Docker）：

```bash
KUBE_PROXY_IMAGE="registry.k8s.io/kube-proxy:v1.36.2"
sudo docker run --privileged --network=host \
  -v /lib/modules:/lib/modules:ro \
  --rm "${KUBE_PROXY_IMAGE}" \
  /bin/sh -c "kube-proxy --cleanup && echo DONE"
```

如果节点上没有 Docker、只安装有 containerd，使用 `ctr` 以特权模式和 host network 启动同一镜像：

```bash
KUBE_PROXY_IMAGE="registry.k8s.io/kube-proxy:v1.36.2"
sudo ctr run --privileged --net-host --rm \
  --mount type=bind,src=/lib/modules,dst=/lib/modules,options=rbind:ro \
  "${KUBE_PROXY_IMAGE}" \
  kube-proxy-cleanup \
  /bin/sh -c "kube-proxy --cleanup && echo DONE"
```

命令末尾出现 `DONE` 表示 `kube-proxy --cleanup` 正常结束。不要将 `iptables -F`、`nft flush ruleset` 或 `ipvsadm -C` 作为默认清理方式；这些命令会清除主机上的非 Kubernetes 规则，可能影响宿主机防火墙、NAT 或其他本地网络配置。

> [!TIP]
> 如果 `kubeadm reset` 报错退出，可以追加 `--force` 参数强制执行。`--force` 会跳过部分前置检查，在 kubelet 无法正常启动或集群状态异常时仍可完成重置。
