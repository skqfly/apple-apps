---
title: "WSL 2 配置：安装、备份与迁移"
pubDate: 2025-10-16
description: "以 Ubuntu 22.04 为例，区分 Windows 与 Linux 命令，整理迁移和日常配置。"
author: "skqfly"
category: "Linux"
image: {"url":"/logo.svg","alt":"skqfly 标志"}
---

WSL 2 的配置经常跨越两个环境：Windows 负责发行版的安装和管理，Ubuntu 负责 Linux 用户、软件与服务。先分清命令在哪里执行，比记住所有参数更重要。

下面沿用 Ubuntu 22.04 作为示例。`D:\WSL` 是 Windows 路径，`/etc/wsl.conf` 是发行版内部路径，不能直接混用。

## 1. 安装并确认 WSL 2

在管理员 PowerShell 中执行：

```powershell
wsl --install -d Ubuntu-22.04
```

根据提示重启，并完成 Ubuntu 首次启动时的用户名和密码设置。随后在 PowerShell 中检查：

```powershell
wsl --list --verbose
wsl --status
```

确认发行版的 `VERSION` 为 `2`。设置后续安装默认使用 WSL 2，与转换现有发行版是两件不同的事：

```powershell
# 后续安装默认使用 WSL 2
wsl --set-default-version 2

# 现有发行版若仍为 WSL 1，可转换为 WSL 2
wsl --set-version Ubuntu-22.04 2

# 指定默认启动的发行版
wsl --set-default Ubuntu-22.04
```

执行转换前，先备份重要数据。

## 2. 导出备份，再导入新位置

在 PowerShell 中创建目标目录。停止发行版前，先保存工作并关闭其中的服务。

```powershell
New-Item -ItemType Directory -Force D:\WSL | Out-Null
wsl --terminate Ubuntu-22.04
wsl --export Ubuntu-22.04 D:\WSL\ubuntu22.04.tar
Get-Item D:\WSL\ubuntu22.04.tar
```

先用一个新名字导入到目标位置，保留原发行版用于核对：

```powershell
wsl --import Ubuntu-22.04-Moved D:\WSL\Ubuntu22.04-Moved D:\WSL\ubuntu22.04.tar --version 2
wsl -d Ubuntu-22.04-Moved
```

进入后检查主目录、项目文件和重要服务。确认导入完整、备份可用，再设置新的默认发行版：

```powershell
wsl --set-default Ubuntu-22.04-Moved
```

> `wsl --unregister` 会永久删除指定发行版的数据。下面是确认迁移成功之后才需要的可选清理步骤，不要在备份验证前执行。

```powershell
wsl --unregister Ubuntu-22.04
```

## 3. 为导入的发行版设置默认用户

导入后的发行版可能默认以 root 登录。先在 Ubuntu 内检查原有用户：

```bash
getent passwd skqfly
```

若用户名不同，使用实际存在的账号。编辑 `/etc/wsl.conf`，保留文件已有配置，仅新增或修改 `[user]` 段：

```bash
sudo nano /etc/wsl.conf
```

```ini
[user]
default=skqfly
```

回到 PowerShell，终止并重新打开该发行版：

```powershell
wsl --terminate Ubuntu-22.04-Moved
wsl -d Ubuntu-22.04-Moved
```

也可以临时指定登录用户：

```powershell
wsl -d Ubuntu-22.04-Moved --user skqfly
```

这与在 Ubuntu 内执行 `su - skqfly` 不同：前者指定一次 WSL 启动的用户，后者只切换当前 Linux 会话。

## 4. 按版本选择软件源

软件源必须匹配发行版代号与 CPU 架构。先在 Ubuntu 中确认：

```bash
. /etc/os-release
printf '%s\n' "$VERSION_CODENAME"
dpkg --print-architecture
```

Ubuntu 22.04 的代号为 `jammy`。以下是使用传统 `sources.list` 的 **amd64 Ubuntu 22.04** 示例；其他版本或 ARM 系统应按 [镜像站说明](https://mirrors.ustc.edu.cn/help/ubuntu.html) 选择对应源。

```bash
sudo cp -a /etc/apt/sources.list /etc/apt/sources.list.bak
sudo nano /etc/apt/sources.list
```

```text
deb https://mirrors.ustc.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb https://mirrors.ustc.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb https://mirrors.ustc.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
deb https://mirrors.ustc.edu.cn/ubuntu/ jammy-security main restricted universe multiverse
```

```bash
sudo apt update
```

如果系统使用 `/etc/apt/sources.list.d/ubuntu.sources`，它属于 deb822 格式，不要直接把上面的传统格式覆盖进去。

## 5. 图形界面按需安装

命令行开发通常不需要完整 Ubuntu 桌面。需要运行单个 Linux GUI 应用时，先确认当前 Windows 与 WSL 环境是否支持 WSLg，再安装目标应用。

```powershell
wsl --update
```

只有确实需要完整桌面环境，并准备好对应显示或远程桌面方案时，才考虑：

```bash
sudo apt install --no-install-recommends ubuntu-desktop-minimal
```

安装桌面软件包本身不等于已经配置好图形登录。也不建议为了“精简”直接批量删除或锁定不熟悉的系统服务。

## 6. 安装 Docker Desktop

从 [Docker 官方说明](https://docs.docker.com/desktop/setup/install/windows-install/) 获取安装程序并确认系统要求。以下命令在安装程序所在目录的 **Windows CMD** 中执行，使用自定义安装和 WSL 数据路径：

```bat
start /w "" "Docker Desktop Installer.exe" install --installation-dir="D:\Program Files\Docker" --wsl-default-data-root="D:\DockerData"
```

这些参数对应支持该选项的全用户安装方式，需要相应权限；其他安装模式以当前安装程序说明为准。安装后启用 WSL 2 后端，并在 WSL Integration 中选择需要使用 Docker 的发行版。

进入该发行版检查：

```bash
docker version
docker run --rm hello-world
```

如果只有客户端信息而连接不到服务端，先检查 Docker Desktop 是否启动，以及发行版集成是否开启。

## 参考资料

- [WSL 基本命令](https://learn.microsoft.com/en-us/windows/wsl/basic-commands)
- [WSL 用户与配置文件](https://learn.microsoft.com/en-us/windows/wsl/wsl-config)
- [WSL 图形应用](https://learn.microsoft.com/en-us/windows/wsl/tutorials/gui-apps)
- [Ubuntu 镜像使用说明](https://mirrors.ustc.edu.cn/help/ubuntu.html)
- [Docker Desktop Windows 安装](https://docs.docker.com/desktop/setup/install/windows-install/)
