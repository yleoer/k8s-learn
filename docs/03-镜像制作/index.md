# 镜像制作

本阶段从 Dockerfile 基础指令开始，逐步掌握镜像构建、构建缓存、多架构镜像和镜像优化方法。先理解每条指令的作用和组合方式，再通过完整的业务镜像制作流程，把前端静态站点和 Go 后端服务分别构建成可发布的生产级镜像。本阶段的任务是：

- 理解 Dockerfile 的作用和常用指令。
- 掌握 FROM、RUN、CMD、ENTRYPOINT、COPY、ADD、ENV、ARG、WORKDIR、USER、LABEL、HEALTHCHECK 等核心指令的组合使用。
- 理解 Shell 与 Exec 格式的区别，正确选择 CMD 和 ENTRYPOINT 的配合方式。
- 理解镜像分层机制和构建缓存优化策略。
- 学会使用多阶段构建减小镜像体积。
- 能够构建 ARM / x86 多架构镜像。
- 掌握 .dockerignore、镜像大小优化和构建上下文管理。
- 按标准流程制作前端静态站点、PHP Web 应用和 Go 后端服务镜像。
- 了解镜像安全和非 root 运行的基本原则。

## 目录

| 文档 | 内容 |
| --- | --- |
| [Dockerfile 快速入门](./1-Dockerfile快速入门) | 指令总览、FROM 基础镜像、RUN 构建命令、LABEL 元数据、HEALTHCHECK 健康检查、缓存策略与编写原则 |
| [CMD、ENTRYPOINT、ENV 与 ARG](./2-CMD与ENTRYPOINT与ENV与ARG) | 容器启动命令、Shell/Exec 格式、环境变量、构建参数及四者的配合 |
| [COPY、ADD、WORKDIR 与 USER](./3-COPY与ADD与WORKDIR与USER) | 文件复制与权限控制、工作目录、非 root 用户运行 |
| [镜像分层与体积优化](./4-镜像分层与体积优化) | docker history 分层查看、多阶段构建、基础镜像选择、.dockerignore 与优化清单 |
| [多架构镜像构建](./5-多架构镜像构建) | Docker Buildx 使用、跨架构构建和推送注意事项 |
| [业务镜像实战：前端、PHP 与 Go 后端](./6-业务镜像实战) | 前端 nginx 静态站点 + PHP Composer 多阶段构建 + Go 多阶段构建，三个完整范例、标准流程与发布检查清单 |
