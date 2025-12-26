# Tuna 前后端分离项目

## 项目结构

```
tuna/
├── api/              # 用户端API模块
├── admin/            # 管理端API模块
├── config/           # 配置模块
├── database/         # 数据库连接模块
├── models/           # 数据模型和仓库
├── sql/              # SQL初始化脚本
├── frontend/         # 前端页面
│   ├── user/         # 用户端页面
│   └── admin/        # 管理端页面
├── go.mod            # Go模块文件
└── main.go           # 主程序入口
```

## 数据库配置

- Host: 127.0.0.1
- Port: 6666
- User: agile
- Password: agile
- Database: tuna
- Table: user_info_tab

## 初始化数据库

执行以下SQL命令创建数据库和表：

```bash
mysql -h 127.0.0.1 -P 6666 -u agile -pagile < sql/init.sql
```

或者直接在MySQL客户端执行 `sql/init.sql` 文件中的内容。

## 安装依赖

```bash
go mod download
```

## 运行后端

```bash
go run main.go
```

后端将启动两个服务：
- API服务（用户端）: http://localhost:8812
- Admin服务（管理端）: http://localhost:8813

## 访问前端

- 用户端: 在浏览器中打开 `frontend/user/index.html`
- 管理端: 在浏览器中打开 `frontend/admin/index.html`

## API接口

### 用户端API (端口8812)

- `POST /api/submit` - 提交用户资料
  ```json
  {
    "name": "张三",
    "email": "zhangsan@example.com",
    "phone": "13800138000",
    "hobby": "阅读",
    "age": 25
  }
  ```

- `GET /api/health` - 健康检查

### 管理端API (端口8813)

- `GET /admin/users` - 获取所有用户列表
- `PUT /admin/users/:id/status` - 更新用户审核状态
  ```json
  {
    "status": "approved"  // 或 "rejected"
  }
  ```
- `GET /admin/health` - 健康检查

## 环境变量（可选）

可以通过环境变量覆盖默认配置：

- `DB_HOST` - 数据库主机（默认: 127.0.0.1）
- `DB_PORT` - 数据库端口（默认: 6666）
- `DB_USER` - 数据库用户名（默认: agile）
- `DB_PASSWORD` - 数据库密码（默认: agile）
- `DB_NAME` - 数据库名（默认: tuna）
- `API_PORT` - API服务端口（默认: 8812）
- `ADMIN_PORT` - Admin服务端口（默认: 8813）

