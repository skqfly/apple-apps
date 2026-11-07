---
title: "用 systemd 管理 Linux 服务"
pubDate: 2025-10-03
description: "以 frpc 为例，配置开机自启、异常重启和日志排查。"
author: "skqfly"
category: "Linux"
image: {"url":"/logo.svg","alt":"skqfly 标志"}
---

终端里的程序运行正常，不代表关闭 SSH 后它还会继续运行。对需要长期运行的进程，可以交给 systemd 管理：统一启动方式，记录日志，并在异常退出后尝试重启。

下面以 Ubuntu 上的 frpc 为例。示例沿用用户 `skqfly` 和目录 `/home/skqfly/frp`；使用前将它们替换成实际用户与路径。

## 1. 先验证程序能独立运行

先检查文件，再以前台方式启动。这样可以把程序自身的问题与 systemd 配置问题分开排查。

```bash
ls -l /home/skqfly/frp/frpc
/home/skqfly/frp/frpc -c /home/skqfly/frp/frpc.toml
```

确认连接正常后，按 `Ctrl+C` 退出。如果可信的程序文件没有执行权限，可补上：

```bash
chmod u+x /home/skqfly/frp/frpc
```

## 2. 创建服务文件

编辑 `/etc/systemd/system/frpc.service`：

```bash
sudo nano /etc/systemd/system/frpc.service
```

写入以下配置。程序由普通用户运行；配置和目录也需要允许该用户读取。

```ini
[Unit]
Description=FRP Client
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=skqfly
WorkingDirectory=/home/skqfly/frp
ExecStart=/home/skqfly/frp/frpc -c /home/skqfly/frp/frpc.toml
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

几个容易混淆的字段：

- `WorkingDirectory`：程序的工作目录，不等于可执行文件的位置。
- `ExecStart`：启动命令，使用绝对路径。它不是普通 shell 命令行，不能直接照搬管道或重定向。
- `Restart=on-failure`：异常退出时重启；主动停止服务不会因此反复启动。
- `After` 与 `Wants`：请求网络就绪相关目标并安排启动顺序，不保证远端服务器一定可达。

注释应独立成行，不要在配置值后追加解释。需要换行的启动命令也应遵循 systemd 的续行规则。

## 3. 加载配置并启用服务

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now frpc
systemctl status frpc --no-pager
```

`daemon-reload` 让 systemd 重新读取单元文件；`enable --now` 同时设置开机自启并立即启动。已有服务文件修改后，还需要重启服务才能应用新的启动参数：

```bash
sudo systemctl daemon-reload
sudo systemctl restart frpc
```

## 4. 日常管理与日志

```bash
# 查看最近的日志
journalctl -u frpc -n 50 --no-pager

# 持续跟踪日志，按 Ctrl+C 退出
journalctl -u frpc -f

# 重启或停止
sudo systemctl restart frpc
sudo systemctl stop frpc

# 取消开机自启，并立即停止
sudo systemctl disable --now frpc
```

如果当前账号没有读取服务日志的权限，在 `journalctl` 前加 `sudo`。

## 5. 启动失败时检查什么

遇到 `status=203/EXEC`，先检查 `ExecStart` 路径、执行权限和二进制架构；它不只表示“缺少执行权限”。

```bash
systemctl cat frpc
ls -l /home/skqfly/frp/frpc
file /home/skqfly/frp/frpc
uname -m
journalctl -u frpc -b --no-pager
```

如果服务显示运行中但连接失败，再排查 frpc 配置、认证信息和网络。可以先检查配置语法：

```bash
/home/skqfly/frp/frpc verify -c /home/skqfly/frp/frpc.toml
```

运行 frps 时，同样可以创建 `frps.service`，将名称、可执行文件和配置路径改为 frps。运行账号还必须具备绑定目标端口的权限。

## 6. 确认开机自启

```bash
systemctl is-enabled frpc
systemctl is-active frpc
```

两条命令分别检查自启状态和当前运行状态。下次正常重启后，再查看 `systemctl status frpc` 与本次启动日志，确认服务确实自动恢复。

## 参考资料

- [systemd 服务配置](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html)
- [systemd 配置文件语法](https://www.freedesktop.org/software/systemd/man/latest/systemd.syntax.html)
- [frp 安装与 systemd 管理](https://gofrp.org/en/docs/setup/)
