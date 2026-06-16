# 镜像仓库

镜像仓库是容器化交付链路的枢纽。第 03 章学会了制作镜像，这些镜像需要存放在一个统一的地方才能被 Kubernetes、CI/CD 和各环境拉取。本阶段从镜像仓库的基本概念开始，逐步完成 Harbor 私有仓库的安装、镜像管理、权限控制和日常运维。本阶段的任务是：

- 理解镜像仓库的作用和镜像地址命名规范。
- 掌握 Harbor 的下载、安装和基本配置。
- 能够向 Harbor 推送和拉取镜像。
- 配置 Docker 和 containerd 对接 Harbor（含 HTTP / 自签证书场景）。
- 理解 Harbor 的项目、用户、角色和权限体系。
- 为 Kubernetes 配置 imagePullSecrets 拉取私有镜像。
- 掌握镜像清理、保留策略、垃圾回收和跨仓库复制。
- 了解磁盘监控和日常运维要点。

## 目录

| 文档 | 内容 |
| --- | --- |
| [镜像仓库概述](./1-镜像仓库概述) | 仓库概念、镜像命名格式、多架构镜像存储、常见操作流程 |
| [Harbor 安装部署](./2-Harbor安装部署) | 下载安装包、配置文件、docker compose 部署、Web 控制台 |
| [Harbor 镜像管理](./3-Harbor镜像管理) | 项目创建、推送拉取、insecure-registry 配置（Docker + containerd） |
| [Harbor 权限管理](./4-Harbor权限管理) | 用户、角色、项目划分、CI/CD 账号、imagePullSecrets |
| [Harbor 运维管理](./5-Harbor运维管理) | 镜像清理、保留策略、垃圾回收、复制同步、磁盘监控 |
