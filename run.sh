#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置
API_PORT=${API_PORT:-8812}
ADMIN_PORT=${ADMIN_PORT:-8813}
GOC_SERVER_PORT=${GOC_SERVER_PORT:-7777}
PID_DIR="./pids"
API_PID_FILE="$PID_DIR/api.pid"
ADMIN_PID_FILE="$PID_DIR/admin.pid"
GOC_SERVER_PID_FILE="$PID_DIR/goc-server.pid"
LOG_DIR="./logs"
API_LOG_FILE="$LOG_DIR/api.log"
ADMIN_LOG_FILE="$LOG_DIR/admin.log"
GOC_SERVER_LOG_FILE="$LOG_DIR/goc-server.log"
BIN_DIR="./bin"
EXECUTABLE="$BIN_DIR/tuna"

# 创建必要的目录
mkdir -p "$PID_DIR" "$LOG_DIR" "$BIN_DIR"

# 检查端口是否被占用
check_port() {
    local port=$1
    local pid=$(lsof -ti:$port 2>/dev/null)
    if [ -n "$pid" ]; then
        echo "$pid"
        return 0
    fi
    return 1
}

# 停止占用端口的进程
kill_port_process() {
    local port=$1
    local service_name=$2
    
    local pid=$(check_port $port)
    if [ -n "$pid" ]; then
        echo -e "${YELLOW}端口 $port 被进程 $pid 占用，正在停止...${NC}"
        kill -9 $pid 2>/dev/null
        sleep 1
        
        # 再次检查是否成功停止
        if check_port $port >/dev/null 2>&1; then
            echo -e "${RED}警告: 无法停止占用端口 $port 的进程${NC}"
            return 1
        else
            echo -e "${GREEN}端口 $port 已释放${NC}"
            return 0
        fi
    fi
    return 0
}

# 启动 goc server
start_goc_server() {
    echo -e "${GREEN}正在启动 goc server...${NC}"
    
    # 检查 goc 命令是否存在
    if ! command -v goc &> /dev/null; then
        echo -e "${RED}错误: 未找到 goc 命令，请确保 goc 已安装并在 PATH 中${NC}"
        return 1
    fi
    
    # 检查 goc server 是否已经在运行
    if [ -f "$GOC_SERVER_PID_FILE" ]; then
        local old_pid=$(cat "$GOC_SERVER_PID_FILE")
        if ps -p $old_pid > /dev/null 2>&1; then
            echo -e "${YELLOW}goc server 已经在运行 (PID: $old_pid)${NC}"
            return 0
        else
            rm -f "$GOC_SERVER_PID_FILE"
        fi
    fi
    
    # 检查 goc server 端口是否被占用
    if check_port $GOC_SERVER_PORT >/dev/null 2>&1; then
        echo -e "${YELLOW}goc server 端口 $GOC_SERVER_PORT 被占用，正在清理...${NC}"
        kill_port_process $GOC_SERVER_PORT "goc server"
    fi
    
    # 启动 goc server
    nohup goc server > "$GOC_SERVER_LOG_FILE" 2>&1 &
    local pid=$!
    echo $pid > "$GOC_SERVER_PID_FILE"
    
    # 等待 goc server 启动
    sleep 2
    
    # 检查 goc server 是否成功启动
    if ps -p $pid > /dev/null 2>&1; then
        echo -e "${GREEN}goc server 启动成功 (PID: $pid, 端口: $GOC_SERVER_PORT)${NC}"
        return 0
    else
        echo -e "${RED}goc server 启动失败，请查看日志: $GOC_SERVER_LOG_FILE${NC}"
        rm -f "$GOC_SERVER_PID_FILE"
        return 1
    fi
}

# 停止 goc server
stop_goc_server() {
    echo -e "${GREEN}正在停止 goc server...${NC}"
    
    if [ -f "$GOC_SERVER_PID_FILE" ]; then
        local pid=$(cat "$GOC_SERVER_PID_FILE")
        if ps -p $pid > /dev/null 2>&1; then
            echo -e "${YELLOW}正在停止 goc server (PID: $pid)...${NC}"
            kill $pid 2>/dev/null
            sleep 2
            
            if ps -p $pid > /dev/null 2>&1; then
                kill -9 $pid 2>/dev/null
                sleep 1
            fi
        fi
        rm -f "$GOC_SERVER_PID_FILE"
    fi
    
    # 清理端口占用
    kill_port_process $GOC_SERVER_PORT "goc server"
    
    echo -e "${GREEN}goc server 已停止${NC}"
}

# 构建可执行文件（使用 goc build 进行插桩编译）
build_executable() {
    echo -e "${GREEN}正在使用 goc build 构建可执行文件（插桩编译）...${NC}"
    
    if [ ! -f "go.mod" ]; then
        echo -e "${RED}错误: 未找到 go.mod 文件，请确保在项目根目录运行${NC}"
        return 1
    fi
    
    # 检查 goc 命令是否存在
    if ! command -v goc &> /dev/null; then
        echo -e "${RED}错误: 未找到 goc 命令，请确保 goc 已安装并在 PATH 中${NC}"
        return 1
    fi
    
    # 确保 goc server 已启动
    if ! start_goc_server; then
        echo -e "${RED}无法启动 goc server，构建失败${NC}"
        return 1
    fi
    
    # 使用 goc build 进行插桩编译
    if goc build -o "$EXECUTABLE" main.go; then
        echo -e "${GREEN}构建成功: $EXECUTABLE${NC}"
        return 0
    else
        echo -e "${RED}构建失败${NC}"
        return 1
    fi
}

# 停止服务
stop_service() {
    local service=$1
    local service_name=""
    
    case $service in
        api)
            service_name="API"
            ;;
        admin)
            service_name="Admin"
            ;;
        *)
            echo -e "${RED}错误: 未知的服务 '$service'，支持的服务: api, admin${NC}"
            exit 1
            ;;
    esac
    
    # 由于API和Admin运行在同一个进程中，我们需要停止整个进程
    # 尝试从任一PID文件读取进程ID
    local pid=""
    if [ -f "$API_PID_FILE" ]; then
        pid=$(cat "$API_PID_FILE")
    elif [ -f "$ADMIN_PID_FILE" ]; then
        pid=$(cat "$ADMIN_PID_FILE")
    fi
    
    # 如果PID文件不存在，尝试通过端口查找进程
    if [ -z "$pid" ] || ! ps -p $pid > /dev/null 2>&1; then
        # 尝试通过API端口查找
        pid=$(check_port $API_PORT)
        if [ -z "$pid" ]; then
            # 尝试通过Admin端口查找
            pid=$(check_port $ADMIN_PORT)
        fi
    fi
    
    if [ -n "$pid" ] && ps -p $pid > /dev/null 2>&1; then
        echo -e "${YELLOW}正在停止服务 (PID: $pid)...${NC}"
        kill $pid 2>/dev/null
        sleep 2
        
        # 如果还在运行，强制杀死
        if ps -p $pid > /dev/null 2>&1; then
            kill -9 $pid 2>/dev/null
            sleep 1
        fi
    fi
    
    # 清理PID文件
    rm -f "$API_PID_FILE" "$ADMIN_PID_FILE"
    
    # 清理端口占用（两个端口都清理）
    kill_port_process $API_PORT "API"
    kill_port_process $ADMIN_PORT "Admin"
    
    echo -e "${GREEN}$service_name 服务已停止${NC}"
}

# 启动服务
start_service() {
    local service=$1
    local port=""
    local pid_file=""
    local log_file=""
    local service_name=""
    
    case $service in
        api)
            port=$API_PORT
            pid_file=$API_PID_FILE
            log_file=$API_LOG_FILE
            service_name="API"
            ;;
        admin)
            port=$ADMIN_PORT
            pid_file=$ADMIN_PID_FILE
            log_file=$ADMIN_LOG_FILE
            service_name="Admin"
            ;;
        *)
            echo -e "${RED}错误: 未知的服务 '$service'${NC}"
            exit 1
            ;;
    esac
    
    # 检查端口是否被占用
    if check_port $port >/dev/null 2>&1; then
        echo -e "${YELLOW}端口 $port 被占用，正在清理...${NC}"
        kill_port_process $port "$service_name"
    fi
    
    # 检查服务是否已经在运行
    if [ -f "$pid_file" ]; then
        local old_pid=$(cat "$pid_file")
        if ps -p $old_pid > /dev/null 2>&1; then
            echo -e "${YELLOW}$service_name 服务已经在运行 (PID: $old_pid)${NC}"
            return 0
        else
            rm -f "$pid_file"
        fi
    fi
    
    # 先启动 goc server（确保 goc server 运行）
    if ! start_goc_server; then
        echo -e "${RED}无法启动 goc server，启动失败${NC}"
        return 1
    fi
    
    # 构建可执行文件（如果不存在或需要重新构建）
    if [ ! -f "$EXECUTABLE" ]; then
        if ! build_executable; then
            echo -e "${RED}无法构建可执行文件，启动失败${NC}"
            return 1
        fi
    fi
    
    # 启动服务
    echo -e "${GREEN}正在启动 $service_name 服务 (端口: $port)...${NC}"
    
    # 使用环境变量来区分启动api还是admin
    if [ "$service" == "api" ]; then
        # 只启动API服务
        # 注意：由于main.go同时启动两个服务，我们需要修改启动方式
        # 这里我们通过环境变量来控制启动哪个服务
        export SERVICE_TYPE=api
        nohup "$EXECUTABLE" > "$log_file" 2>&1 &
    else
        # 只启动Admin服务
        export SERVICE_TYPE=admin
        nohup "$EXECUTABLE" > "$log_file" 2>&1 &
    fi
    
    local pid=$!
    echo $pid > "$pid_file"
    
    # 等待服务启动
    sleep 2
    
    # 检查服务是否成功启动
    if ps -p $pid > /dev/null 2>&1; then
        echo -e "${GREEN}$service_name 服务启动成功 (PID: $pid, 端口: $port)${NC}"
        return 0
    else
        echo -e "${RED}$service_name 服务启动失败${NC}"
        rm -f "$pid_file"
        return 1
    fi
}

# 启动所有服务
start_all() {
    echo -e "${GREEN}正在启动所有服务...${NC}"
    
    # 先启动 goc server
    if ! start_goc_server; then
        echo -e "${RED}无法启动 goc server，启动失败${NC}"
        return 1
    fi
    
    # 检查并清理端口
    kill_port_process $API_PORT "API"
    kill_port_process $ADMIN_PORT "Admin"
    
    # 构建可执行文件（如果不存在或需要重新构建）
    if [ ! -f "$EXECUTABLE" ]; then
        if ! build_executable; then
            echo -e "${RED}无法构建可执行文件，启动失败${NC}"
            return 1
        fi
    fi
    
    # 启动服务（由于main.go同时启动两个服务，我们只需要启动一次）
    echo -e "${GREEN}正在启动服务 (API端口: $API_PORT, Admin端口: $ADMIN_PORT)...${NC}"
    
    if [ -f "$API_PID_FILE" ] || [ -f "$ADMIN_PID_FILE" ]; then
        local old_pid=""
        if [ -f "$API_PID_FILE" ]; then
            old_pid=$(cat "$API_PID_FILE")
        elif [ -f "$ADMIN_PID_FILE" ]; then
            old_pid=$(cat "$ADMIN_PID_FILE")
        fi
        
        if [ -n "$old_pid" ] && ps -p $old_pid > /dev/null 2>&1; then
            echo -e "${YELLOW}服务已经在运行 (PID: $old_pid)${NC}"
            return 0
        fi
    fi
    
    # 启动服务（使用编译后的可执行文件，main.go会同时启动api和admin）
    nohup "$EXECUTABLE" > "$LOG_DIR/service.log" 2>&1 &
    local pid=$!
    echo $pid > "$API_PID_FILE"
    echo $pid > "$ADMIN_PID_FILE"
    
    # 等待服务启动
    sleep 3
    
    # 检查服务是否成功启动
    if ps -p $pid > /dev/null 2>&1; then
        echo -e "${GREEN}服务启动成功 (PID: $pid)${NC}"
        echo -e "${GREEN}  - API服务运行在端口: $API_PORT${NC}"
        echo -e "${GREEN}  - Admin服务运行在端口: $ADMIN_PORT${NC}"
        return 0
    else
        echo -e "${RED}服务启动失败，请查看日志: $LOG_DIR/service.log${NC}"
        rm -f "$API_PID_FILE" "$ADMIN_PID_FILE"
        return 1
    fi
}

# 停止所有服务
stop_all() {
    echo -e "${GREEN}正在停止所有服务...${NC}"
    
    # 停止API服务
    if [ -f "$API_PID_FILE" ]; then
        local pid=$(cat "$API_PID_FILE")
        if ps -p $pid > /dev/null 2>&1; then
            echo -e "${YELLOW}正在停止服务 (PID: $pid)...${NC}"
            kill $pid 2>/dev/null
            sleep 2
            
            if ps -p $pid > /dev/null 2>&1; then
                kill -9 $pid 2>/dev/null
            fi
        fi
        rm -f "$API_PID_FILE"
    fi
    
    # 停止Admin服务（如果PID文件不同）
    if [ -f "$ADMIN_PID_FILE" ] && [ "$ADMIN_PID_FILE" != "$API_PID_FILE" ]; then
        local pid=$(cat "$ADMIN_PID_FILE")
        if ps -p $pid > /dev/null 2>&1; then
            kill $pid 2>/dev/null
            sleep 1
            if ps -p $pid > /dev/null 2>&1; then
                kill -9 $pid 2>/dev/null
            fi
        fi
        rm -f "$ADMIN_PID_FILE"
    fi
    
    # 清理端口占用
    kill_port_process $API_PORT "API"
    kill_port_process $ADMIN_PORT "Admin"
    
    echo -e "${GREEN}所有服务已停止${NC}"
    echo -e "${YELLOW}注意: goc server 仍在运行，如需停止请使用: $0 stop-goc${NC}"
}

# 主逻辑
case "$1" in
    build)
        build_executable
        ;;
    start)
        start_all
        ;;
    restart)
        echo -e "${YELLOW}正在重启服务...${NC}"
        stop_all
        sleep 2
        start_all
        ;;
    stop)
        if [ -z "$2" ]; then
            echo -e "${RED}错误: 请指定要停止的服务 (api 或 admin)${NC}"
            echo "用法: $0 stop api|admin"
            exit 1
        fi
        stop_service "$2"
        ;;
    start-goc)
        start_goc_server
        ;;
    stop-goc)
        stop_goc_server
        ;;
    *)
        echo "用法: $0 {build|start|restart|stop api|admin|start-goc|stop-goc}"
        echo ""
        echo "命令说明:"
        echo "  build          - 使用 goc build 构建可执行文件（插桩编译）"
        echo "  start          - 启动 goc server、API 和 Admin 服务（会自动构建）"
        echo "  restart        - 重启 API 和 Admin 服务"
        echo "  stop api       - 停止 API 服务并清理端口占用"
        echo "  stop admin     - 停止 Admin 服务并清理端口占用"
        echo "  start-goc      - 启动 goc server"
        echo "  stop-goc       - 停止 goc server"
        exit 1
        ;;
esac

exit 0

