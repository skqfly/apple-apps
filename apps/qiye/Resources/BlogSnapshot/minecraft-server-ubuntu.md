---
title: "在 Ubuntu 24.04 部署 Minecraft 服务器"
pubDate: 2025-10-05
description: "从安装 Java 到首次启动，再用 systemd 保持服务运行。"
author: "skqfly"
category: "Game"
image: {"url":"/logo.svg","alt":"skqfly 标志"}
---

这篇笔记面向 Minecraft Java 版原版服务器，以 Ubuntu 24.04、Minecraft 1.21.x 和 Java 21 为示例环境。客户端与服务端版本需要一致；其他版本或模组服务端应先确认各自的 Java 要求。

先让服务端以前台方式成功启动，再配置开机自启。这样出现问题时，可以更快定位到具体步骤。

## 1. 安装 Java

```bash
sudo apt update
sudo apt install -y openjdk-21-jre-headless
java -version
```

这里安装运行环境即可，不需要为了运行服务器额外安装完整开发工具。输出应包含 Java 21；如果机器上有多个 Java 版本，检查实际执行路径：

```bash
command -v java
readlink -f "$(command -v java)"
```

不要把“下载最新服务端”与固定 Java 版本直接配对。升级 Minecraft 前，应重新核对目标版本的运行要求。

## 2. 准备独立目录与服务端文件

以下操作使用普通登录用户执行，示例用户为 `skqfly`。

```bash
mkdir -p ~/minecraft
cd ~/minecraft
```

从 [Minecraft 官方服务端下载页](https://www.minecraft.net/zh-hans/download/server) 或目标版本的官方发布说明获取对应 JAR，放入该目录，统一命名为 `server.jar`。

检查文件已经放好：

```bash
ls -lh ~/minecraft/server.jar
```

不使用从网页文字中拼接下载地址的脚本，以免下载到错误版本或无效文件。

## 3. 首次启动并确认 EULA

```bash
cd ~/minecraft
java -Xms1G -Xmx4G -jar server.jar nogui
```

`-Xms1G` 表示初始堆内存为 1 GiB，`-Xmx4G` 表示最大堆内存为 4 GiB；`nogui` 表示不启动图形界面。它们是示例参数，需要为操作系统和 Java 堆外内存保留空间。

首次启动通常会生成配置文件，并因尚未接受 EULA 而退出。阅读 [Minecraft EULA](https://www.minecraft.net/eula)，同意后编辑 `eula.txt`：

```bash
nano eula.txt
```

```properties
eula=true
```

如果没有生成文件，先检查终端中的实际错误，不要把所有启动失败都归因于 EULA。

## 4. 再次启动并连接

```bash
java -Xms1G -Xmx4G -jar server.jar nogui
```

看到服务器就绪日志后，在同一局域网内使用服务器的局域网地址连接：

```text
服务器的局域网 IP:25565
```

原版 Java 服务器默认使用 `25565/tcp`。如已启用 UFW，可按需要放行：

```bash
sudo ufw allow 25565/tcp
```

公网访问还需要云安全组或路由器端口转发；没有公网入口的家庭网络可使用 [frp](/blog/frp-setup)。不要把面板端口与游戏端口混为一谈。

测试结束后，在服务器控制台输入 `stop` 正常退出，避免与后面的 systemd 服务争用端口。

## 5. 配置开机自启

编辑服务文件：

```bash
sudo nano /etc/systemd/system/minecraft.service
```

下面沿用 `skqfly` 用户与 `/home/skqfly/minecraft` 目录。请先确认用户、JAR 和 Java 路径存在，再按实际情况修改。

```ini
[Unit]
Description=Minecraft Java Server
After=network.target

[Service]
Type=simple
User=skqfly
WorkingDirectory=/home/skqfly/minecraft
ExecStart=/usr/bin/java -Xms1G -Xmx4G -jar server.jar nogui
Restart=on-failure
RestartSec=10s
TimeoutStopSec=120s

[Install]
WantedBy=multi-user.target
```

先使用简洁的启动参数，等服务器稳定运行、确实存在性能问题后，再根据测量结果调整 JVM。不要把带行尾解释的多行命令直接写进 `ExecStart`。

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now minecraft
systemctl status minecraft --no-pager
journalctl -u minecraft -n 50 --no-pager
```

## 6. 维护与排查

- **Java 版本不匹配**：出现 `UnsupportedClassVersionError` 时，核对服务端要求与 systemd 使用的 Java 路径。
- **端口已被占用**：检查是否还开着前台服务端。
- **本机可连、外网不可连**：分别检查游戏端口、防火墙、云安全组与路由器转发。
- **更新或备份世界**：先正常停止服务，备份世界目录和配置，再替换服务端文件。不要在没有备份时直接跨版本升级。

```bash
sudo ss -lntp | grep ':25565'
sudo systemctl stop minecraft
sudo systemctl start minecraft
```

## 参考资料

- [Minecraft 服务端下载](https://www.minecraft.net/zh-hans/download/server)
- [Java 21 要求的官方说明](https://www.minecraft.net/en-us/article/minecraft-java-edition-1-20-5)
- [systemd 服务配置](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html)
