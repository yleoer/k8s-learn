# Harbor 漏洞扫描

[镜像供应链安全](./6-镜像供应链安全.md) 记录了 SBOM、签名和准入的可信链路，漏洞扫描是其中独立的一环：回答“镜像里已知漏洞有哪些、严重到什么程度”。本文记录 Harbor 的扫描器架构、扫描策略、高风险镜像阻断和 CVE 允许清单。

## 扫描器架构

Harbor 通过 scanner adapter 对接漏洞扫描器。Trivy 是内置扫描器，[Harbor 安装部署](./2-Harbor安装部署.md) 中使用 `--with-trivy` 安装后，`trivy-adapter` 组件负责承接扫描任务。Clair 自 Harbor v2.2 起不再作为默认扫描器提供，存量集群仍可将其作为外部扫描器接入，但旧文档中的内置 Clair 配置已不适用。

除内置 Trivy 外，Harbor 支持接入符合 Pluggable Scanner 规范的外部扫描器：在 **系统管理 → 审查服务（Interrogation Services）→ 新建扫描器** 中登记地址与认证方式，可设为全局默认；项目还可以在自身的 **扫描器** 标签页选择项目级扫描器，覆盖全局默认。

扫描对象与边界：

- 扫描针对镜像等 OCI 制品，扫描器按声明的 MIME 类型决定是否支持某类制品，Helm chart 等制品不会被 Trivy 扫描。
- 多架构镜像（OCI image index）的扫描结果由其引用的各平台制品聚合而来。
- Cosign 签名制品不支持扫描。

## 扫描方式

Harbor 提供三种触发方式，覆盖单个制品、全量存量和增量推送：

| 方式     | 操作位置                                  | 说明                     |
|--------|---------------------------------------|------------------------|
| 手动扫描   | 项目 → 镜像仓库 → 勾选制品 → 扫描                 | 针对单个制品，处于排队或扫描中时不能重复发起 |
| 全量扫描   | 系统管理 → 审查服务 → Vulnerability 标签 → 立即扫描 | 扫描全部制品，资源消耗大，建议低峰执行    |
| 定时全量扫描 | 同上，编辑扫描计划                             | 支持每小时、每天、每周或自定义 cron   |
| 推送时扫描  | 项目 → 配置管理 → 勾选“自动扫描镜像”                | 新推送制品自动进入扫描队列          |

扫描结果按严重级别汇总，Harbor 使用的级别从高到低为 Critical、High、Medium、Low、Negligible、Unknown，无漏洞时为 None。制品详情页可以查看每个 CVE 的编号、受影响包、当前版本和修复版本。

## 阻止拉取高风险镜像

项目 **配置管理** 中的“阻止潜在漏洞镜像”（Prevent vulnerable images from running）策略按严重级别阻断镜像分发。虽然名字是 running，它实际拦截的是拉取：漏洞级别等于或高于所选阈值的镜像无法被 `docker pull` 或节点拉取。

使用时需要记录的行为细节：

- 判定依据是项目所选扫描器（未单独设置时为全局默认扫描器）的结果，不同扫描器对同一镜像的级别评定可能不同。
- Negligible 级别永远不会触发阻断。
- 拉取多架构镜像时，策略只检查实际拉取的平台制品，不受同一 index 下其他架构漏洞的影响。

> [!WARNING]
> 阻断对 Kubernetes 节点同样生效：Pod 调度后节点拉取镜像被 Harbor 拒绝，表现为 `ImagePullBackOff`。启用该策略前应先完成存量镜像扫描，并为无法立即修复的 CVE 规划允许清单，否则可能直接阻断正常发布。

## CVE 允许清单

允许清单（CVE allowlist）把特定 CVE 从扫描判定中排除，常用于确认不可利用、暂无修复版本但业务必须发布的场景。清单中的 CVE 在“阻止拉取”判断中被忽略。

Harbor 提供两级清单：

| 级别  | 配置位置                    | 生效范围             |
|-----|-------------------------|------------------|
| 系统级 | 系统管理 → 配置管理 → 安全 → 部署安全 | 默认应用于所有项目        |
| 项目级 | 项目 → 配置管理 → CVE 允许清单    | 选择“项目允许清单”后覆盖系统级 |

CVE ID 支持逗号或换行分隔批量添加。两级清单都支持设置过期时间：取消“永不过期”后选择到期日，到期后清单条目自动失效，避免临时豁免变成永久豁免。

项目级清单可以通过“复制系统允许清单”初始化，但此后与系统清单不再自动同步；系统清单更新后，各项目需要重新复制或手动维护。

## Trivy 漏洞库更新

Trivy 依赖漏洞数据库判定 CVE，数据库的更新方式决定扫描结果的时效：

- 联网环境（默认）：Trivy 自动下载 `trivy-db` 并缓存本地。Harbor v2.15 的 `harbor.yml` 支持通过 `trivy.db_repository` 指定 OCI 数据库仓库，默认值为 `ghcr.io/aquasecurity/trivy-db`；Java 漏洞数据库可通过 `java_db_repository` 单独配置。上游 trivy-db 每 6 小时构建一次，数据库元数据默认更新间隔为 24 小时。
- 离线环境：`harbor.yml` 中设置 `skip_update: true` 停用在线下载，手动下载离线数据库包并将 `trivy.db` 与 `metadata.json` 放入 trivy-adapter 容器的 `/home/scanner/.cache/trivy/db`；同时设置 `offline_scan: true` 阻止扫描过程中的外部 API 请求。两个开关需要同时开启，只开其中一个仍会产生外网访问。

## 记录要点

- 扫描器返回的是“已知漏洞清单”，不证明镜像可信，签名与来源证明仍需按供应链安全的方式单独建设。
- 阻断策略上线顺序：先开启推送时扫描，再全量扫描存量，评估影响后才启用阻止拉取。
- 允许清单条目应记录豁免原因和到期时间，到期复审而不是无限续期。
- 漏洞库时效直接影响判定结果，离线实例应把数据库更新纳入例行运维。

## 参考

- [Vulnerability Scanning](https://goharbor.io/docs/2.15.0/administration/vulnerability-scanning/)
- [Scan Individual Artifacts](https://goharbor.io/docs/2.15.0/administration/vulnerability-scanning/scan-individual-artifact/)
- [Scan All Artifacts](https://goharbor.io/docs/2.15.0/administration/vulnerability-scanning/scan-all-artifacts/)
- [Connect Harbor to Additional Vulnerability Scanners](https://goharbor.io/docs/2.15.0/administration/vulnerability-scanning/pluggable-scanners/)
- [Configure System-Wide CVE Allowlists](https://goharbor.io/docs/2.15.0/administration/vulnerability-scanning/configure-system-allowlist/)
- [Configure a Per-Project CVE Allowlist](https://goharbor.io/docs/2.15.0/working-with-projects/project-configuration/configure-project-allowlist/)
- [Configure Project Settings](https://goharbor.io/docs/2.15.0/working-with-projects/project-configuration/)
- [Harbor Configuration File](https://goharbor.io/docs/2.15.0/install-config/configure-yml-file/)
