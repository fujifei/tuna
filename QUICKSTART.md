# 快速启动指南

## 1. 初始化数据库

首先，确保MySQL服务正在运行，然后执行以下命令创建数据库和表：

```bash
mysql -h 127.0.0.1 -P 6666 -u agile -pagile < sql/init.sql
```

或者直接在MySQL客户端中执行 `sql/init.sql` 文件的内容。

## 2. 安装Go依赖

```bash
go mod download
```

## 3. 启动后端服务

```bash
go run main.go
```

启动后，你会看到：
- API服务（用户端）运行在: http://localhost:8812
- Admin服务（管理端）运行在: http://localhost:8813

## 4. 访问前端页面

### 用户端
直接在浏览器中打开文件：
```
frontend/user/index.html
```

或者使用本地服务器（推荐）：
```bash
# 使用Python启动简单HTTP服务器
cd frontend/user
python3 -m http.server 3000
# 然后访问 http://localhost:3000
```

### 管理端
直接在浏览器中打开文件：
```
frontend/admin/index.html
```

或者使用本地服务器（推荐）：
```bash
# 使用Python启动简单HTTP服务器
cd frontend/admin
python3 -m http.server 3001
# 然后访问 http://localhost:3001
```

## 测试流程

1. 在用户端页面填写并提交用户资料
2. 在管理端页面查看提交的用户列表
3. 在管理端点击"通过"或"拒绝"按钮进行审核
4. 审核后，用户状态会更新并在列表中显示

## 注意事项

- 确保MySQL服务正在运行且可以连接到指定的端口
- 如果遇到CORS问题，确保后端服务已启动
- 前端页面需要与后端服务在同一网络环境下，或者修改前端代码中的API地址

