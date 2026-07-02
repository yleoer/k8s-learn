# 业务镜像实战

本附录基于前面章节中的 Dockerfile 指令、变量、文件操作、分层优化和多架构构建方法，整理前端、PHP 与 Go 后端三类常见业务镜像范例。

## 制作前检查

制作业务镜像前，应先明确以下信息：

1. 应用启动命令是什么？监听哪个端口？
2. 配置来自环境变量、配置文件还是配置中心？
3. 是否需要非 root 运行？健康检查端点是什么？
4. 日志是写到文件还是 stdout/stderr？
5. 预期内存和 CPU 在什么范围？

明确上述信息后，再编写 Dockerfile，可以减少运行命令、权限、健康检查和资源配置之间的不一致。

## 范例一：前端静态站点

场景：Vue / React 构建产物或纯 HTML 静态页面，由 nginx 托管。

### 项目结构

```text
frontend/
├── Dockerfile
├── .dockerignore
└── src/
    ├── index.html
    ├── style.css
    └── app.js
```

### .dockerignore

```text
.git
node_modules
*.log
.DS_Store
README.md
```

### 静态文件

`src/index.html`：

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>K8s 演示平台</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <div class="container">
    <h1>Kubernetes 演示平台</h1>
    <p>版本：<span id="version">v1.0.0</span></p>
  </div>
  <script src="app.js"></script>
</body>
</html>
```

`src/style.css`：

```css
body {
  font-family: system-ui, sans-serif;
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: 100vh;
  margin: 0;
  background: #f5f5f5;
}
.container {
  text-align: center;
  padding: 2rem;
  background: white;
  border-radius: 8px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
}
```

`src/app.js`：

```javascript
document.getElementById('version').textContent = 'v1.0.0';
```

### Dockerfile

```dockerfile
FROM nginx:1.27-alpine
LABEL maintainer="platform@example.com"
LABEL org.opencontainers.image.title="frontend"
LABEL org.opencontainers.image.version="1.0.0"

COPY src/ /usr/share/nginx/html/

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1:80/ || exit 1

EXPOSE 80
```

关键点：静态文件只需 `COPY`；`nginx:1.27-alpine` 自带 `wget`，可用于健康检查；nginx worker 自动以非 root 身份运行；静态文件已是最终产物，通常不需要多阶段构建。

### 构建、运行、验证

```bash
docker build -t harbor.example.com/team/frontend:v1.0.0 .
```

> 使用 BuildKit（Docker Engine 默认构建后端）时，`docker build` 等效于 `docker buildx build`。部分旧版文档使用 `DOCKER_BUILDKIT=1 docker build`，在新版本中已无需手动设置。

```bash
docker run -d --name frontend \
  --memory 128m --cpus 0.25 \
  -p 8080:80 \
  harbor.example.com/team/frontend:v1.0.0

curl -s http://127.0.0.1:8080 | grep '<h1>'
docker ps --filter name=frontend
```

<details>
<summary>docker ps 输出类似如下</summary>

```text
$ docker ps --filter name=frontend
CONTAINER ID   IMAGE                                     COMMAND                  CREATED          STATUS                             PORTS                               NAMES
f0b201388ff8   harbor.example.com/team/frontend:v1.0.0   "/docker-entrypoint.…"   12 seconds ago   Up 11 seconds (health: starting)   0.0.0.0:8080->80/tcp, [::]:8080->80/tcp   frontend
```

</details>

## 范例二：PHP Web 应用

场景：PHP 8.3 + Apache，Composer 管理依赖，Monolog 记录日志，内置 `/healthz` 端点。

### 项目结构

```text
php-app/
├── Dockerfile
├── .dockerignore
├── composer.json
└── public/
    └── index.php
```

### .dockerignore

```text
.git
*.log
.DS_Store
README.md
vendor/
```

> `vendor/` 在 `.dockerignore` 中排除，因为它会在构建阶段由 Composer 重新安装，放入构建上下文只会拖慢速度。

### composer.json

```json
{
  "name": "example/php-app",
  "require": {
    "php": ">=8.3",
    "monolog/monolog": "^3.0"
  }
}
```

### public/index.php

```php
<?php
require_once __DIR__ . '/../vendor/autoload.php';

use Monolog\Logger;
use Monolog\Handler\StreamHandler;

$log = new Logger('app');
$log->pushHandler(new StreamHandler('php://stdout', Logger::INFO));

$uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);

header('Content-Type: application/json');

if ($uri === '/healthz') {
    echo json_encode([
        'status'  => 'ok',
        'version' => getenv('APP_VERSION') ?: '1.0.0',
        'time'    => date('c'),
    ]);
    exit;
}

if ($uri === '/api/hello') {
    $log->info('hello endpoint called');
    echo json_encode(['message' => 'Hello from PHP on K8s!']);
    exit;
}

http_response_code(404);
echo json_encode(['error' => 'not found']);
```

### Dockerfile

```dockerfile
# === 依赖安装阶段 ===
FROM composer:2 AS vendor
WORKDIR /app
COPY composer.json ./
RUN composer install --no-dev --no-interaction --prefer-dist --no-scripts

# === 运行阶段 ===
FROM php:8.3-apache
LABEL maintainer="platform@example.com"
LABEL org.opencontainers.image.title="php-app"
LABEL org.opencontainers.image.version="1.0.0"

# 安装 wget（供 HEALTHCHECK 使用）并启用 opcache
RUN apt-get update \
    && apt-get install -y --no-install-recommends wget \
    && rm -rf /var/lib/apt/lists/* \
    && docker-php-ext-install opcache

ENV APP_VERSION=1.0.0

# 将不存在的路径交给 index.php 处理，支持 /healthz 和 /api/hello
RUN printf '%s\n' \
      '<Directory /var/www/html>' \
      '    FallbackResource /index.php' \
      '</Directory>' \
      > /etc/apache2/conf-available/app.conf \
    && a2enconf app

COPY --from=vendor /app/vendor/ /var/www/vendor/
COPY public/ /var/www/html/

RUN chown -R www-data:www-data /var/www

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1:80/healthz || exit 1

EXPOSE 80
```

关键点：

- **多阶段构建**：`composer:2` 安装依赖，最终镜像不包含 Composer 本身，可减少运行镜像体积。
- **依赖安装**：示例只复制 `composer.json`，Composer 在构建阶段解析并安装依赖；生产项目建议提交 `composer.lock` 并一同复制，以保证依赖版本可复现。
- **依赖路径**：`public/index.php` 通过 `../vendor/autoload.php` 加载依赖，因此 `vendor/` 需要复制到 `/var/www/vendor/`。
- **请求路由**：Apache 默认只按真实文件路径查找资源，`FallbackResource /index.php` 可将 `/healthz`、`/api/hello` 等路径交给入口文件处理。
- **合并 RUN**：`apt-get install`、`docker-php-ext-install` 和清理步骤在同一层完成。
- **运行身份**：Apache 子进程以 `www-data` 运行，`chown` 确保站点文件可读。
- **opcache**：PHP 字节码缓存可减少重复解析开销。
- **日志输出**：Monolog Handler 设置为 `php://stdout`，由容器运行时统一收集。

### 构建、运行、验证

```bash
docker build -t harbor.example.com/team/php-app:v1.0.0 .
```

```bash
docker run -d --name php-app \
  --memory 256m --cpus 0.5 \
  -p 8081:80 \
  harbor.example.com/team/php-app:v1.0.0

curl http://127.0.0.1:8081/healthz
curl http://127.0.0.1:8081/api/hello
```

```text
{"status":"ok","version":"1.0.0","time":"<RFC3339 时间>"}
{"message":"Hello from PHP on K8s!"}
```

## 范例三：Go 后端微服务

场景：Go 1.23 编写的小型 API 服务，多阶段构建，最终基于 Alpine 运行。

### 项目结构

```text
backend/
├── Dockerfile
├── .dockerignore
├── go.mod
├── go.sum
└── main.go
```

### .dockerignore

```text
.git
*.log
.DS_Store
README.md
```

### main.go

```go
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"
)

func main() {
	port := getEnv("APP_PORT", "8080")

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"status":  "ok",
			"version": getEnv("APP_VERSION", "1.0.0"),
			"time":    time.Now().UTC().Format(time.RFC3339),
		})
	})
	mux.HandleFunc("/api/hello", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"message": "Hello from Go on K8s!",
		})
	})

	log.Printf("server starting on :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, mux))
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
```

### go.mod

```text
module github.com/example/backend

go 1.23
```

本示例未引用第三方模块，`go.sum` 可保留为空文件：

```bash
touch go.sum
```

### Dockerfile

```dockerfile
# === 构建阶段 ===
FROM golang:1.23-alpine AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /app/server .

# === 运行阶段 ===
FROM alpine:3.20
LABEL maintainer="platform@example.com"
LABEL org.opencontainers.image.title="backend"
LABEL org.opencontainers.image.version="1.0.0"

RUN apk add --no-cache ca-certificates tzdata wget

ENV APP_PORT=8080 \
    APP_VERSION=1.0.0

RUN addgroup -S app && adduser -S app -G app
WORKDIR /app
COPY --from=builder --chown=app:app /app/server /app/server

USER app
EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["/app/server"]
```

关键点：

- **多阶段构建**：`golang:1.23-alpine` 仅用于编译，最终 Alpine 镜像不含 Go 工具链。
- **静态编译**：`CGO_ENABLED=0` 不依赖 glibc；`-ldflags="-s -w"` 去除调试符号。
- **缓存优化**：`go.mod/go.sum` 先复制 → `go mod download` → 最后 `COPY . .`，源码改动时依赖下载层被缓存。
- **非 root**：创建 `app` 用户并以 `USER app` 运行，配合 `COPY --chown` 赋予文件所有权。
- **运行时依赖**：`ca-certificates`（HTTPS）、`tzdata`（时区）、`wget`（健康检查）是 Alpine 最小镜像的常见补充。
- **Exec 格式 CMD**：信号直接送达 Go 进程，`docker stop` 可触发 `SIGTERM` 优雅退出。

### 构建、运行、验证

```bash
docker build -t harbor.example.com/team/backend:v1.0.0 .
```

```bash
docker run -d --name backend \
  --memory 256m --cpus 0.5 \
  -p 8082:8080 \
  harbor.example.com/team/backend:v1.0.0

curl http://127.0.0.1:8082/healthz
curl http://127.0.0.1:8082/api/hello
```

```text
{"status":"ok","version":"1.0.0","time":"<RFC3339 时间>"}
{"message":"Hello from Go on K8s!"}
```

确认镜像大小，输出会随基础镜像版本、构建平台和本地 Docker image store 变化：

```bash
docker images harbor.example.com/team/backend:v1.0.0
```

```text
IMAGE                                    ID             DISK USAGE   CONTENT SIZE   EXTRA
harbor.example.com/team/backend:v1.0.0   5c9706869b6c       17.1MB             0B    U
```

## 三个范例对照

| 对比项 | 前端 | PHP | Go |
| --- | --- | --- | --- |
| 基础镜像 | `nginx:1.27-alpine` | `php:8.3-apache` | `alpine:3.20` |
| 构建阶段数 | 1 | 2（composer → php） | 2（golang → alpine） |
| 非 root 方式 | nginx 自动处理 | Apache `www-data` | `USER app` |
| HEALTHCHECK | `wget /` | `wget /healthz` | `wget /healthz` |
| 配置注入 | 构建时 COPY | 环境变量 | 环境变量 |
| 日志输出 | 自动 stdout | Monolog → `php://stdout` | 自动 stdout |
| 最终体积 | ~45 MB | ~180 MB | ~17-19 MB |

三个范例对应不同语言和构建模式，但共同关注固定版本、非 root、健康检查、stdout 日志和资源限制。
