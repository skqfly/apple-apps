---
title: "frp 内网穿透：SSH 与网站访问"
pubDate: 2025-10-03
description: "配置 frps 与 frpc，将内网 SSH 和 HTTP 服务映射到公网入口。"
author: "skqfly"
category: "Linux"
image: {"url":"/logo.svg","alt":"skqfly 标志"}
---

frp 由两部分组成：公网服务器运行 `frps`，内网机器运行 `frpc`。客户端主动连接服务端，再把指定的内网服务转发出去。

本文保留原笔记使用的 **v0.65.0** 作为安装示例，不代表当前最新版。示例分别映射 SSH 和 HTTP 网站，公网地址、域名与认证令牌都需要替换。

## 1. 下载对应架构的程序

在公网服务器和内网机器上分别执行 `uname -m`。常见对应关系为 `x86_64 → amd64`、`aarch64 → arm64`，不能只根据设备名称选择压缩包。

x86_64 Linux 示例：

```bash
wget https://github.com/fatedier/frp/releases/download/v0.65.0/frp_0.65.0_linux_amd64.tar.gz
tar -xzf frp_0.65.0_linux_amd64.tar.gz
mv frp_0.65.0_linux_amd64 frp
cd frp
```

64 位树莓派使用同一版本的 `linux_arm64` 压缩包，并相应调整文件名。两端优先使用相同版本；从 [官方 Releases](https://github.com/fatedier/frp/releases) 获取文件并核对发布信息。

## 2. 配置公网服务端

在公网服务器的 frp 目录创建 `frps.toml`：

```toml
bindPort = 7000
vhostHTTPPort = 8080
subDomainHost = "example.com"

auth.method = "token"
auth.token = "REPLACE_WITH_A_LONG_RANDOM_TOKEN"

webServer.addr = "127.0.0.1"
webServer.port = 7500
webServer.user = "admin"
webServer.password = "REPLACE_WITH_A_STRONG_PASSWORD"
```

- `7000`：接收 frpc 的连接。
- `8080`：接收转发到内网网站的 HTTP 请求，避开已有 Nginx 常用的 80 端口。
- `example.com`：用于子域名转发的基础域名。
- `7500`：可选控制台，这里仅监听本机；不需要时可删除四个 `webServer` 字段。

运行前必须替换令牌和密码，客户端使用同一个认证令牌。配置里采用完整的点分键名，避免把 `auth` 误写进 `[webServer]` 表中。

检查语法并以前台方式启动：

```bash
./frps verify -c ./frps.toml
./frps -c ./frps.toml
```

## 3. 配置内网客户端

在内网机器上创建 `frpc.toml`。把 `frp.example.com` 替换成公网服务器地址。

```toml
serverAddr = "frp.example.com"
serverPort = 7000

auth.method = "token"
auth.token = "REPLACE_WITH_A_LONG_RANDOM_TOKEN"

[[proxies]]
name = "ssh"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = 60022

[[proxies]]
name = "blog"
type = "http"
localIP = "127.0.0.1"
localPort = 8888
subdomain = "blog"
```

SSH 通过服务端的 `60022/tcp` 进入内网机器的 22 端口。网站使用 HTTP 类型，通过 Host 匹配 `blog.example.com`，再转发到内网的 `127.0.0.1:8888`。

先确认内网服务确实存在，再运行 frpc：

```bash
curl -I http://127.0.0.1:8888/
./frpc verify -c ./frpc.toml
./frpc -c ./frpc.toml
```

## 4. 配置 DNS 和公网端口

将 `frp.example.com` 与 `blog.example.com` 的 DNS 记录指向公网服务器。只转发一个网站时，为 `blog` 添加明确的记录即可，不必先配置通配符域名。

按用途配置公网服务器防火墙和云安全组：

- `7000/tcp`：供内网 frpc 连接。
- `60022/tcp`：供授权的 SSH 用户连接，尽量限制来源地址。
- `8080/tcp`：供网站访问；若由同机 Nginx 接入，则可以只暴露 Nginx 的端口。
- 控制台的 `7500` 只监听回环地址，无需对公网开放。

从外部电脑验证：

```bash
ssh -p 60022 用户名@frp.example.com
curl -I http://blog.example.com:8080/
```

当前网站示例是 HTTP。需要 HTTPS 时，可在公网 Nginx 终止 TLS，再代理至 frps 的 HTTP 端口，并保留 `Host` 请求头。不要只添加 `vhostHTTPSPort` 就认为证书已经配置完成。

## 5. 交给 systemd 运行

前台测试正常后，用 `Ctrl+C` 停止测试进程，再参考 [systemd 服务管理笔记](/blog/linux-service-autostart) 创建对应单元文件：

- 公网服务器：`frps.service`，启动 `frps -c /实际路径/frps.toml`。
- 内网机器：`frpc.service`，启动 `frpc -c /实际路径/frpc.toml`。

单元文件存在后，分别在相应机器执行：

```bash
# 公网服务器
sudo systemctl daemon-reload
sudo systemctl enable --now frps

# 内网机器
sudo systemctl daemon-reload
sudo systemctl enable --now frpc
```

## 6. 常见问题

**连接超时**：检查服务端地址、监听端口、防火墙和安全组。先看日志，再测试网络。

```bash
# 公网服务器
sudo ss -lntp | grep ':7000'
journalctl -u frps -n 50 --no-pager

# 内网机器
nc -vz frp.example.com 7000
journalctl -u frpc -n 50 --no-pager
```

**认证失败**：两端令牌必须完全一致，也要检查 TOML 字段是否处于正确层级。

**程序无法执行**：核对执行权限、CPU 架构与文件路径；`203/EXEC` 不一定只是权限问题。

**能连 frps，但网站打不开**：检查内网 8888 端口是否工作，以及 DNS、HTTP 入口端口和 Host 是否匹配。

**端口占用**：确认没有另一个前台进程，或其他服务已经占用 `7000`、`8080`、`60022`。

## 参考资料

- [frp 安装与运行](https://gofrp.org/en/docs/setup/)
- [服务端配置字段](https://gofrp.org/en/docs/reference/server-configures/)
- [HTTP 与 HTTPS 转发](https://gofrp.org/en/docs/features/http-https/)
