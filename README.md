# Aim Trainer · Godot 客户端 + 云端服务器

练枪训练器现在只有 **Godot 客户端**一个版本，云端服务器负责账号注册/登录、成绩记录和全服排行榜。

## 组成

- `godot/`：Godot 4.3+ 桌面客户端（三种模式、计分、管理员辅助功能、云端登录）
- `server.js`：纯 API 服务器（注册、登录、成绩上传、排行榜），数据保存在服务器 `data/` 目录

## 服务器部署

```bash
npm install
npm start
```

默认端口 3000。云端账号、成绩、排行榜都通过以下接口工作：

- `POST /api/register` 注册
- `POST /api/login` 登录
- `POST /api/score` 上传成绩
- `GET /api/leaderboard?mode=sixshot|tracking|gridshot` 排行榜前十

⚠️ 客户端从其他电脑连接时，云服务器需要在安全组/防火墙放行 **TCP 3000** 端口。

## Godot 客户端

运行方式见 [godot/README.md](godot/README.md)。

登录界面输入服务器地址（默认 `http://123.207.58.61:3000`）、用户名和密码，点「登录 / 注册」即可（没有账号会自动注册）。勾选「自动登录」后本机会记住账号密码，下次启动直接进入。

游戏内按 Esc 弹出菜单：**继续** / **退出**（退出回主菜单）。
