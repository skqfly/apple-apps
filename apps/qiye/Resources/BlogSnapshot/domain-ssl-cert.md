---
title: "Nginx 反向代理与 HTTPS 配置测试"
pubDate: 2025-10-09
description: "为本机服务绑定域名，用 Certbot 申请证书并验证自动续期。"
author: "skqfly"
category: "Linux"
image: {"url":"/logo.svg","alt":"skqfly 标志"}
---

一个服务已经在服务器的 `127.0.0.1:40301` 上运行，接下来希望通过域名和 HTTPS 访问。本文以 Ubuntu 的 Nginx 软件包和 Certbot 为例，依次处理 DNS、反向代理与证书。

示例使用 `panel.example.com`，需要替换成自己的域名。若应用还有安全入口路径，例如 `/skqfly`，访问时保留该路径；不要把它硬塞到所有反向代理请求里。

## 1. 检查服务与域名解析

先在服务器本机确认应用能够响应：

```bash
curl -I http://127.0.0.1:40301/
```

应用返回登录跳转或需要入口路径，不一定意味着服务未启动。应结合实际地址和服务日志判断。

在 DNS 服务商处添加 A 记录：以 `panel.example.com` 为例，主机记录通常填写 `panel`，记录值为服务器公网 IPv4。只有根域名才通常使用 `@`。

```bash
dig +short panel.example.com A
dig +short panel.example.com AAAA
```

A 记录应指向目标服务器。若同时存在 AAAA 记录，IPv6 也必须能正确访问；不正确的 IPv6 记录可能影响证书验证。

## 2. 安装 Nginx 与 Certbot

如果已经由 1Panel、容器或其他服务管理 80、443 端口，先确认端口归属，不要另起一套冲突的 Nginx。

```bash
sudo ss -lntp | grep -E ':(80|443)'
sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx
sudo systemctl enable --now nginx
```

这是 Ubuntu 软件源安装方式。使用其他 Certbot 安装方式时，按对应官方说明操作，避免混装多个版本。

## 3. 创建反向代理站点

编辑站点文件：

```bash
sudo nano /etc/nginx/sites-available/panel.example.com
```

```nginx
server {
    listen 80;
    server_name panel.example.com;

    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:40301;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    access_log /var/log/nginx/panel_access.log;
    error_log /var/log/nginx/panel_error.log;
}
```

这里的 `proxy_pass` 只写上游地址，不附加 URI。根据 [Nginx 的路径转发规则](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_pass)，请求中的路径会传给上游，因此 `/skqfly` 仍由应用处理。

WebSocket 相关请求头用于终端等需要协议升级的功能。实际应用若提供了专用反向代理配置，应优先对照其说明调整。

## 4. 启用站点并检查配置

Ubuntu 软件包通常通过 `sites-enabled` 加载站点。首次启用时创建软链接；如果链接已经存在，就不要重复创建。

```bash
sudo ln -s /etc/nginx/sites-available/panel.example.com /etc/nginx/sites-enabled/panel.example.com
sudo nginx -t
```

只在检查通过后重新加载：

```bash
sudo systemctl reload nginx
```

此时先测试 HTTP 访问，确认域名、入口路径和静态资源都能正常工作，再进入证书步骤。

## 5. 申请 HTTPS 证书

确保公网可以访问该域名的 80 端口，并按需放行 443 端口；这同时涉及服务器防火墙和云安全组。

```bash
sudo certbot --nginx -d panel.example.com --redirect
```

按当前版本的提示填写账户信息并阅读条款。`--redirect` 用于将 HTTP 请求跳转到 HTTPS，不依赖教程截图里的菜单编号。

申请完成后检查：

```bash
sudo nginx -t
sudo certbot certificates
curl -I https://panel.example.com/
```

如果应用设置了安全入口，实际登录地址应类似 `https://panel.example.com/skqfly`。HTTPS 可用并不等于入口路径可以省略。

## 6. 验证续期与排查问题

```bash
sudo certbot renew --dry-run
systemctl list-timers --all | grep -i certbot
```

`dry-run` 用于测试续期流程。定时任务的名称和管理方式取决于安装方式，不能仅凭一次申请成功就认定自动续期已配置。

常见问题：

- **证书验证失败**：检查 A/AAAA 记录、80 端口、域名代理或 CDN 设置。
- **502 Bad Gateway**：先测试本机上游地址，再检查应用监听协议、端口和 Nginx 错误日志。
- **首页能开但资源或登录失败**：核对路径转发、应用外部地址配置和安全入口。
- **证书正常但浏览器仍有提醒**：查看具体原因，例如混合内容或证书域名不匹配，不以图标颜色作为判断依据。

```bash
sudo tail -n 50 /var/log/nginx/panel_error.log
```

## 参考资料

- [Nginx 反向代理模块](https://nginx.org/en/docs/http/ngx_http_proxy_module.html)
- [Nginx WebSocket 代理](https://nginx.org/en/docs/http/websocket.html)
- [Certbot 使用与续期](https://eff-certbot.readthedocs.io/en/stable/using.html)
