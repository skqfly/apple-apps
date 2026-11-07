---
title: "树莓派 5：用 MCSManager 管理 Minecraft"
pubDate: 2025-10-10
description: "在 Ubuntu 24.04 上安装面板、连接节点，并创建 Java 版游戏实例。"
author: "skqfly"
category: "Game"
image: {"url":"/logo.svg","alt":"skqfly 标志"}
---

MCSManager 把游戏实例的文件、日志和启动命令集中到网页里。下面以树莓派 5 的 64 位 Ubuntu 24.04 为例，将 Web 面板与守护进程部署在同一台机器，再创建 Minecraft Java 版实例。

如果只需要一个后台服务，也可以使用 [不依赖面板的部署方式](/blog/minecraft-server-ubuntu)。

## 1. 安装面板与守护进程

安装前先检查系统架构和现有端口：

```bash
uname -m
sudo ss -lntp
```

64 位 ARM 系统通常显示 `aarch64`。按 [MCSManager 官方安装说明](https://docs.mcsmanager.com/zh_cn/) 确认当前支持的环境。

官方快速安装脚本需要 root 权限。可以先下载、查看内容，再执行：

```bash
sudo apt update
sudo apt install -y curl ca-certificates
curl -fsSL https://script.mcsmanager.com/setup_cn.sh -o /tmp/mcsmanager-setup.sh
less /tmp/mcsmanager-setup.sh
sudo bash /tmp/mcsmanager-setup.sh
```

按安装结果检查两个服务：

```bash
sudo systemctl start mcsm-daemon.service
sudo systemctl start mcsm-web.service
systemctl status mcsm-daemon mcsm-web --no-pager
```

Web 面板默认监听 `23333`，守护进程默认监听 `24444`；如果安装时修改过配置，以实际端口为准。

## 2. 打开面板并配置访问

在树莓派本机打开浏览器时，使用 `http://localhost:23333`；在另一台电脑上访问时，改用树莓派的局域网 IP。

按首次访问页面提示创建管理账号，并保存好密码。确认服务端口可达：

```bash
sudo ss -lntp | grep -E ':(23333|24444)'
```

如果已经启用 UFW，可仅允许管理设备访问面板相关端口。下面的地址是占位示例，需要改成你的电脑 IP：

```bash
sudo ufw allow from 192.168.1.100 to any port 23333 proto tcp
sudo ufw allow from 192.168.1.100 to any port 24444 proto tcp
```

若准备首次启用防火墙，先放行实际使用的 SSH 端口，避免远程连接被切断。公网部署还需要配置云安全组和 HTTPS；不必为了游戏联机向所有人开放管理面板。

## 3. 连接守护进程节点

在面板的节点管理页面查看已有节点。单机安装若已自动建立本地节点，不需要重复添加。

手动添加时填写：

- **地址**：使用官方文档支持的连接地址；同机节点可按说明使用 `localhost`，远程节点则填写对应 IP 或域名。
- **端口**：守护进程端口，默认 `24444`。
- **密钥**：守护进程的节点密钥，不是面板登录密码。

使用官方脚本安装时，节点配置通常位于：

```bash
sudo nano /opt/mcsmanager/daemon/data/Config/global.json
```

读取配置中的 `key`，填入节点管理页面。不要把真实密钥贴进公开文章或截图。

节点在线不代表所有浏览器功能都已连通。如果远程终端、上传或下载失败，还应检查浏览器到节点的网络、WebSocket 和 HTTPS 配置，参照 [分布式部署说明](https://docs.mcsmanager.com/advanced/distributed.html)。

## 4. 为目标版本准备 Java

本文以 Minecraft 1.21.x 原版服务端为例，安装 Java 21：

```bash
sudo apt update
sudo apt install -y openjdk-21-jre-headless
java -version
```

如果安装了多个版本，可以查看并切换默认 Java：

```bash
sudo update-alternatives --config java
```

模组包可能要求不同的 Java 版本。需要同时运行多个版本时，在各实例启动命令中填写对应 Java 的绝对路径，不必反复修改系统默认值。

## 5. 创建并启动游戏实例

在面板中创建 Java 版实例，选择刚才连接的节点。将对应版本的服务端 JAR 上传到实例工作目录，命名为 `server.jar`。

服务端文件从 [Minecraft 官方下载页](https://www.minecraft.net/zh-hans/download/server) 或目标版本发布说明获取。不要把不同版本的客户端、服务端混用。

启动命令：

```bash
java -Xms1G -Xmx4G -jar server.jar nogui
```

这里初始分配 1 GiB 堆内存，最大 4 GiB。根据树莓派实际内存调整，并为系统、面板和堆外内存留出余量。

首次启动通常会生成 `eula.txt`。阅读并同意 [Minecraft EULA](https://www.minecraft.net/eula) 后，在实例文件管理中将其改为：

```properties
eula=true
```

再次启动，检查日志是否显示服务器就绪。游戏连接使用默认 `25565/tcp`，与面板的两个管理端口无关。

## 6. 导入整合包时的区别

整合包不一定用 `java -jar server.jar` 启动。以 [Better MC Forge BMC4](https://www.curseforge.com/minecraft/modpacks/better-mc-forge-bmc4) 这类整合包为例，应下载与目标版本对应的 **Server Pack**，再按包内说明准备 Java、安装加载器并设置启动命令。

- 不要把客户端整合包直接当作服务端上传。
- 优先使用 Server Pack 随附的启动脚本及参数。
- 树莓派还需要确认包内原生库或工具支持 ARM64。
- 首次运行先看日志，确认依赖和内存要求，再考虑自动重启或定时任务。

## 参考资料

- [MCSManager 快速开始](https://docs.mcsmanager.com/zh_cn/)
- [MCSManager 节点与密钥](https://docs.mcsmanager.com/advanced/distributed.html)
- [Minecraft Java 21 要求](https://www.minecraft.net/en-us/article/minecraft-java-edition-1-20-5)
