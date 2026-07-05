# 镜像制作

第 02 章已完成容器核心概念、Docker 架构和基础操作的记录。镜像是容器运行的模板，因此镜像制作是从“使用容器”走向“交付应用”的关键环节。

本章从 Dockerfile 基础指令开始，逐步覆盖构建缓存、分层优化、多阶段构建、多架构镜像发布和 BuildKit 构建挂载与 heredoc，并通过附录补充业务镜像制作范例。这些记录为后续镜像仓库、Kubernetes 应用部署和 CI/CD 发布流程提供可交付的镜像基础。

## 参考

- [Dockerfile reference](https://docs.docker.com/reference/dockerfile/)
- [Docker build cache](https://docs.docker.com/build/cache/)
- [Multi-stage builds](https://docs.docker.com/build/building/multi-stage/)
- [Multi-platform builds](https://docs.docker.com/build/building/multi-platform/)
- [Build context 与 .dockerignore](https://docs.docker.com/build/concepts/context/)
- [Build secrets](https://docs.docker.com/build/building/secrets/)
