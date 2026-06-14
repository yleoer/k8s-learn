# CMD 与 ENTRYPOINT

`CMD` 和 `ENTRYPOINT` 都和容器启动命令有关，但职责不同。

## CMD

`CMD` 表示默认命令，容易被覆盖：

```dockerfile
FROM alpine:3.20
CMD ["echo", "hello"]
```

覆盖：

```bash
docker run --rm demo echo world
```

## ENTRYPOINT

`ENTRYPOINT` 表示容器入口，更适合固定主程序：

```dockerfile
FROM alpine:3.20
ENTRYPOINT ["echo"]
CMD ["hello"]
```

运行默认参数：

```bash
docker run --rm demo
```

追加参数：

```bash
docker run --rm demo world
```

这里 `world` 会替换 `CMD`，作为 `ENTRYPOINT` 的参数。

## 覆盖 ENTRYPOINT

```bash
docker run --rm --entrypoint sh demo
```

## 选择建议

- 只需要默认命令：用 `CMD`。
- 主程序固定，参数可变：用 `ENTRYPOINT` + `CMD`。
- 复杂启动逻辑放到入口脚本，不要把一长串 shell 都塞进 Dockerfile。
