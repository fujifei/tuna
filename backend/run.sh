#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 后端目录（当前脚本所在目录）
BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 项目根目录（backend 的父目录）
PROJECT_ROOT="$(cd "$BACKEND_DIR/.." && pwd)"
CONFIG_FILE="$BACKEND_DIR/config.yaml"
PID_DIR="$PROJECT_ROOT/pids"
LOG_DIR="$PROJECT_ROOT/logs"

# 创建必要的目录
mkdir -p "$PID_DIR" "$LOG_DIR"

# 从配置文件读取配置
load_config() {
    # 默认值
    local default_api_port="8812"
    local default_admin_port="8813"
    local default_goc_wrapper_port="7777"
    local default_rabbitmq_url="amqp://coverage:coverage123@localhost:5672/"
    local default_goc_source_dir="/Users/jifei.fu/project/qa/orbit/goc"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}警告: 配置文件不存在，使用默认配置${NC}"
        API_PORT=${API_PORT:-$default_api_port}
        ADMIN_PORT=${ADMIN_PORT:-$default_admin_port}
        GOC_WRAPPER_PORT=${GOC_WRAPPER_PORT:-$default_goc_wrapper_port}
        RABBITMQ_URL=${RABBITMQ_URL:-$default_rabbitmq_url}
        GOC_SOURCE_DIR=${GOC_SOURCE_DIR:-$default_goc_source_dir}
        return
    fi

    # 尝试使用Python解析YAML文件
    local config_values=""
    if command -v python3 &> /dev/null; then
        config_values=$(python3 <<EOF 2>/dev/null
try:
    import yaml
    with open("$CONFIG_FILE", 'r') as f:
        config = yaml.safe_load(f)
    
    api_port = config.get('ports', {}).get('api', '$default_api_port')
    admin_port = config.get('ports', {}).get('admin', '$default_admin_port')
    goc_wrapper_port = config.get('goc', {}).get('wrapper_port', '$default_goc_wrapper_port')
    rabbitmq_url = config.get('goc', {}).get('rabbitmq_url', '$default_rabbitmq_url')
    goc_source_dir = config.get('goc_build', {}).get('source_dir', '$default_goc_source_dir')
    
    print(f"{api_port}|{admin_port}|{goc_wrapper_port}|{rabbitmq_url}|{goc_source_dir}")
except:
    pass
EOF
)
    fi
    
    # 如果Python解析失败，使用简单的grep/sed方法
    if [ -z "$config_values" ]; then
        local api_port=$(grep -A 2 "^ports:" "$CONFIG_FILE" 2>/dev/null | grep "api:" | sed -E 's/.*api:[[:space:]]*"?([^"]*)"?.*/\1/' | head -1)
        local admin_port=$(grep -A 2 "^ports:" "$CONFIG_FILE" 2>/dev/null | grep "admin:" | sed -E 's/.*admin:[[:space:]]*"?([^"]*)"?.*/\1/' | head -1)
        local goc_wrapper_port=$(grep -A 2 "^goc:" "$CONFIG_FILE" 2>/dev/null | grep "wrapper_port:" | sed -E 's/.*wrapper_port:[[:space:]]*"?([^"]*)"?.*/\1/' | head -1)
        local rabbitmq_url=$(grep -A 3 "^goc:" "$CONFIG_FILE" 2>/dev/null | grep "rabbitmq_url:" | sed -E 's/.*rabbitmq_url:[[:space:]]*"?([^"]*)"?.*/\1/' | head -1)
        local goc_source_dir=$(grep -A 2 "^goc_build:" "$CONFIG_FILE" 2>/dev/null | grep "source_dir:" | sed -E 's/.*source_dir:[[:space:]]*"?([^"]*)"?.*/\1/' | head -1)
        
        config_values="${api_port:-$default_api_port}|${admin_port:-$default_admin_port}|${goc_wrapper_port:-$default_goc_wrapper_port}|${rabbitmq_url:-$default_rabbitmq_url}|${goc_source_dir:-$default_goc_source_dir}"
    fi
    
    # 解析配置值
    IFS='|' read -r api_port admin_port goc_wrapper_port rabbitmq_url goc_source_dir <<< "$config_values"
    
    # 设置变量（环境变量可以覆盖配置文件）
    API_PORT=${API_PORT:-$api_port}
    ADMIN_PORT=${ADMIN_PORT:-$admin_port}
    GOC_WRAPPER_PORT=${GOC_WRAPPER_PORT:-$goc_wrapper_port}
    RABBITMQ_URL=${RABBITMQ_URL:-$rabbitmq_url}
    GOC_SOURCE_DIR=${GOC_SOURCE_DIR:-$goc_source_dir}
}

# 加载配置
load_config

# PID和日志文件
API_PID_FILE="$PID_DIR/api.pid"
ADMIN_PID_FILE="$PID_DIR/admin.pid"
API_LOG_FILE="$LOG_DIR/api.log"
ADMIN_LOG_FILE="$LOG_DIR/admin.log"
GOC_LOG_FILE="$LOG_DIR/goc-server.log"

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

# 检查并准备 goc 可执行文件
ensure_goc() {
    # 先检查本地是否有 goc 可执行文件
    if [ ! -f "$PROJECT_ROOT/goc" ]; then
        # 如果本地没有，检查 PATH 中是否有
        if ! command -v goc &> /dev/null; then
            # 如果都不存在，则构建
            echo -e "${YELLOW}未找到 goc 命令，正在构建 goc...${NC}"
            if ! build_goc; then
                echo -e "${RED}错误: 构建 goc 失败${NC}"
                return 1
            fi
        fi
    else
        # 本地有 goc 文件，确保它在 PATH 中
        export PATH="$PROJECT_ROOT:$PATH"
    fi
    
    # 确定 goc 命令路径
    local goc_cmd="goc"
    if [ -f "$PROJECT_ROOT/goc" ]; then
        goc_cmd="$PROJECT_ROOT/goc"
    fi
    
    echo "$goc_cmd"
    return 0
}

# 构建 goc 可执行文件
build_goc() {
    echo -e "${GREEN}正在构建 goc 可执行文件...${NC}"
    
    local goc_temp_dir="$PROJECT_ROOT/goc_temp"
    local goc_executable="$PROJECT_ROOT/goc"
    
    # 检查并删除现有的 goc 可执行文件
    if [ -f "$goc_executable" ]; then
        echo -e "${YELLOW}发现已存在的 goc 可执行文件，正在删除...${NC}"
        rm -f "$goc_executable"
    fi
    
    # 检查源目录是否存在
    if [ ! -d "$GOC_SOURCE_DIR" ]; then
        echo -e "${RED}错误: 源目录不存在: $GOC_SOURCE_DIR${NC}"
        return 1
    fi
    
    # 如果源目录是 git 仓库，先拉取最新代码
    if [ -d "$GOC_SOURCE_DIR/.git" ]; then
        echo -e "${GREEN}检测到 git 仓库，正在拉取最新代码...${NC}"
        local original_dir_for_git=$(pwd)
        cd "$GOC_SOURCE_DIR" || {
            echo -e "${YELLOW}警告: 无法进入源目录，跳过 git pull${NC}"
            cd "$original_dir_for_git"
        }
        if git pull >/dev/null 2>&1; then
            echo -e "${GREEN}代码已更新${NC}"
        else
            echo -e "${YELLOW}警告: git pull 失败，继续使用现有代码${NC}"
        fi
        cd "$original_dir_for_git" || return 1
    fi
    
    # 1. 删除现有的 goc_temp 目录（如果存在），确保复制最新代码
    if [ -d "$goc_temp_dir" ]; then
        echo -e "${YELLOW}删除现有的 goc_temp 目录...${NC}"
        rm -rf "$goc_temp_dir"
    fi
    
    # 2. 在项目根目录下创建目录 goc_temp
    echo -e "${GREEN}创建 goc_temp 目录...${NC}"
    mkdir -p "$goc_temp_dir"
    
    # 3. 将源目录下的全部文件复制到 goc_temp 中
    echo -e "${GREEN}复制 goc 源文件到 goc_temp...${NC}"
    # 复制所有文件（包括隐藏文件，但排除 .git 目录）
    rsync -a --exclude='.git' "$GOC_SOURCE_DIR/" "$goc_temp_dir/" 2>/dev/null || {
        # 如果 rsync 不可用，使用 cp 命令
        cp -r "$GOC_SOURCE_DIR"/* "$goc_temp_dir/" 2>/dev/null
        cp -r "$GOC_SOURCE_DIR"/.[!.]* "$goc_temp_dir/" 2>/dev/null
    }
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误: 复制文件失败${NC}"
        return 1
    fi
    
    # 4. 进入 goc_temp 目录
    local original_dir=$(pwd)
    cd "$goc_temp_dir" || {
        echo -e "${RED}错误: 无法进入 goc_temp 目录${NC}"
        return 1
    }
    
    # 5. 执行 go mod download 下载
    echo -e "${GREEN}下载 goc 依赖...${NC}"
    if ! go mod download; then
        echo -e "${RED}错误: go mod download 失败${NC}"
        cd "$original_dir"
        return 1
    fi
    
    # 6. 执行 go mod tidy 整理依赖并更新 go.sum
    echo -e "${GREEN}整理 goc 依赖并更新 go.sum...${NC}"
    if ! go mod tidy; then
        echo -e "${RED}错误: go mod tidy 失败${NC}"
        cd "$original_dir"
        return 1
    fi
    
    # 7. 执行 go build 在项目根目录下生成名字为 goc 可执行文件
    echo -e "${GREEN}编译 goc 可执行文件...${NC}"
    if ! go build -o "$PROJECT_ROOT/goc"; then
        echo -e "${RED}错误: go build 失败${NC}"
        cd "$original_dir"
        return 1
    fi
    
    # 返回原目录
    cd "$original_dir" || return 1
    
    # 6. 修改 goc 可执行文件的权限使其可使用
    if [ -f "$goc_executable" ]; then
        chmod +x "$goc_executable"
        echo -e "${GREEN}goc 可执行文件构建成功: $goc_executable${NC}"
        return 0
    else
        echo -e "${RED}错误: goc 可执行文件未生成${NC}"
        return 1
    fi
}

# 构建服务可执行文件（使用 goc build）
build_service() {
    local service=$1
    local service_dir="$BACKEND_DIR/$service"
    local cmd_dir="$service_dir/cmd"
    local executable="$service_dir/$service"
    
    if [ ! -d "$service_dir" ]; then
        echo -e "${RED}错误: 服务目录不存在: $service_dir${NC}"
        return 1
    fi
    
    if [ ! -f "$cmd_dir/main.go" ]; then
        echo -e "${RED}错误: 未找到 $service/cmd/main.go 文件${NC}"
        return 1
    fi
    
    echo -e "${GREEN}正在使用 goc build 构建 $service 服务...${NC}"
    
    # 确保 goc 可执行文件存在
    local goc_cmd=$(ensure_goc)
    if [ $? -ne 0 ]; then
        echo -e "${RED}无法准备 goc 可执行文件，构建失败${NC}"
        return 1
    fi
    
    # 确保依赖已下载（在 backend 目录下）
    local original_dir=$(pwd)
    cd "$BACKEND_DIR" || {
        echo -e "${RED}错误: 无法进入 $BACKEND_DIR 目录${NC}"
        return 1
    }
    
    if ! go mod download >/dev/null 2>&1; then
        echo -e "${YELLOW}警告: go mod download 失败，继续尝试构建...${NC}"
    fi
    
    # 进入 cmd 目录进行编译
    cd "$cmd_dir" || {
        echo -e "${RED}错误: 无法进入 $cmd_dir 目录${NC}"
        cd "$original_dir"
        return 1
    }
    
    # 删除旧的可执行文件
    if [ -f "$executable" ]; then
        rm -f "$executable"
    fi
    
    # 使用 goc build 编译（在 cmd 目录下执行，输出到 service 目录）
    # 添加 --rabbitmq-url 参数
    if $goc_cmd build --rabbitmq-url="$RABBITMQ_URL" -o "$executable" .; then
        echo -e "${GREEN}构建成功: $executable${NC}"
        cd "$original_dir"
        return 0
    else
        echo -e "${RED}构建失败${NC}"
        cd "$original_dir"
        return 1
    fi
}

# 停止服务
stop_service() {
    local service=$1
    local service_name=""
    local port=""
    local pid_file=""
    
    case $service in
        api)
            service_name="API"
            port=$API_PORT
            pid_file=$API_PID_FILE
            ;;
        admin)
            service_name="Admin"
            port=$ADMIN_PORT
            pid_file=$ADMIN_PID_FILE
            ;;
        *)
            echo -e "${RED}错误: 未知的服务 '$service'，支持的服务: api, admin${NC}"
            exit 1
            ;;
    esac
    
    # 从PID文件读取进程ID
    local pid=""
    if [ -f "$pid_file" ]; then
        pid=$(cat "$pid_file")
    fi
    
    # 如果PID文件不存在或进程不存在，尝试通过端口查找进程
    if [ -z "$pid" ] || ! ps -p $pid > /dev/null 2>&1; then
        pid=$(check_port $port)
    fi
    
    if [ -n "$pid" ] && ps -p $pid > /dev/null 2>&1; then
        echo -e "${YELLOW}正在停止 $service_name 服务 (PID: $pid)...${NC}"
        kill $pid 2>/dev/null
        sleep 2
        
        # 如果还在运行，强制杀死
        if ps -p $pid > /dev/null 2>&1; then
            kill -9 $pid 2>/dev/null
            sleep 1
        fi
    fi
    
    # 清理PID文件
    rm -f "$pid_file"
    
    # 清理端口占用
    kill_port_process $port "$service_name"
    
    echo -e "${GREEN}$service_name 服务已停止${NC}"
}

# 启动服务（直接启动编译生成的二进制文件）
start_service() {
    local service=$1
    local port=""
    local pid_file=""
    local log_file=""
    local service_name=""
    local executable=""
    
    case $service in
        api)
            port=$API_PORT
            pid_file=$API_PID_FILE
            log_file=$API_LOG_FILE
            service_name="API"
            executable="$BACKEND_DIR/api/api"
            ;;
        admin)
            port=$ADMIN_PORT
            pid_file=$ADMIN_PID_FILE
            log_file=$ADMIN_LOG_FILE
            service_name="Admin"
            executable="$BACKEND_DIR/admin/admin"
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
    
    # 每次启动时，删除现有的 goc 可执行文件并重新构建（确保使用最新代码）
    echo -e "${GREEN}正在重新构建 goc 可执行文件（拉取最新代码）...${NC}"
    if [ -f "$PROJECT_ROOT/goc" ]; then
        echo -e "${YELLOW}删除现有的 goc 可执行文件...${NC}"
        rm -f "$PROJECT_ROOT/goc"
    fi
    if ! build_goc; then
        echo -e "${RED}错误: 构建 goc 失败${NC}"
        return 1
    fi
    
    # 确保可执行文件存在，如果不存在则构建
    if [ ! -f "$executable" ]; then
        echo -e "${YELLOW}可执行文件不存在，正在构建...${NC}"
        if ! build_service "$service"; then
            echo -e "${RED}无法构建可执行文件，启动失败${NC}"
            return 1
        fi
    fi
    
    # 启动服务（直接启动编译生成的二进制文件）
    echo -e "${GREEN}正在启动 $service_name 服务 (端口: $port)...${NC}"
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}启动命令:${NC}"
    echo -e "${YELLOW}$executable${NC}"
    echo -e "${GREEN}服务日志文件: $log_file${NC}"
    echo -e "${GREEN}RabbitMQ 上报: $RABBITMQ_URL${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    # 启动服务
    # 设置工作目录为 backend 目录，确保配置文件能被正确找到
    # 设置 CONFIG_PATH 环境变量，确保配置文件路径正确
    local original_dir=$(pwd)
    cd "$BACKEND_DIR"
    export CONFIG_PATH="$CONFIG_FILE"
    # 将服务的 stdout 和 stderr 都重定向到日志文件
    nohup "$executable" >> "$log_file" 2>&1 &
    local pid=$!
    cd "$original_dir"
    echo $pid > "$pid_file"
    
    # 等待服务启动
    sleep 3
    
    # 检查服务是否成功启动
    if ps -p $pid > /dev/null 2>&1; then
        echo -e "${GREEN}$service_name 服务启动成功 (PID: $pid, 端口: $port)${NC}"
        echo -e "${GREEN}  RabbitMQ 上报: $RABBITMQ_URL${NC}"
        
        服务启动成功后删除 goc_temp 目录
        if [ -d "$PROJECT_ROOT/goc_temp" ]; then
            echo -e "${YELLOW}正在删除 goc_temp 目录...${NC}"
            rm -rf "$PROJECT_ROOT/goc_temp"
            echo -e "${GREEN}goc_temp 目录已删除${NC}"
        fi
        
        return 0
    else
        echo -e "${RED}$service_name 服务启动失败，请查看日志: $log_file${NC}"
        rm -f "$pid_file"
        return 1
    fi
}

# 主逻辑
case "$1" in
    build)
        if [ -z "$2" ]; then
            echo -e "${RED}错误: 请指定要构建的服务 (api 或 admin)${NC}"
            exit 1
        fi
        build_service "$2"
        ;;
    start)
        if [ -z "$2" ]; then
            echo -e "${RED}错误: 请指定要启动的服务 (api 或 admin)${NC}"
            exit 1
        fi
        start_service "$2"
        ;;
    stop)
        if [ -z "$2" ]; then
            echo -e "${RED}错误: 请指定要停止的服务 (api 或 admin)${NC}"
            exit 1
        fi
        stop_service "$2"
        ;;
    restart)
        if [ -z "$2" ]; then
            echo -e "${RED}错误: 请指定要重启的服务 (api 或 admin)${NC}"
            exit 1
        fi
        echo -e "${YELLOW}正在重启 $2 服务...${NC}"
        stop_service "$2"
        sleep 2
        start_service "$2"
        ;;
    *)
        echo "用法: $0 {build|start|stop|restart} {api|admin}"
        echo ""
        echo "命令说明:"
        echo "  build api    - 使用 goc build 构建 API 服务（在 backend/api/ 目录下生成 api 可执行文件）"
        echo "  build admin  - 使用 goc build 构建 Admin 服务（在 backend/admin/ 目录下生成 admin 可执行文件）"
        echo "  start api    - 启动 API 服务（会自动构建）"
        echo "  start admin  - 启动 Admin 服务（会自动构建）"
        echo "  stop api     - 停止 API 服务并清理端口占用"
        echo "  stop admin   - 停止 Admin 服务并清理端口占用"
        echo "  restart api  - 重启 API 服务"
        echo "  restart admin- 重启 Admin 服务"
        echo ""
        echo "配置文件:"
        echo "  $CONFIG_FILE"
        echo ""
        echo "日志文件:"
        echo "  API日志:   $API_LOG_FILE"
        echo "  Admin日志: $ADMIN_LOG_FILE"
        echo "  GOC日志:   $GOC_LOG_FILE"
        echo ""
        echo "环境变量（可覆盖配置文件）:"
        echo "  API_PORT         - API 服务端口"
        echo "  ADMIN_PORT       - Admin 服务端口"
        echo "  RABBITMQ_URL     - RabbitMQ URL（用于代码覆盖率上报）"
        echo ""
        echo "注意:"
        echo "  - 使用 goc build 编译时会将代码覆盖率收集功能编译进二进制文件"
        echo "  - 编译时会使用 --rabbitmq-url 参数指定覆盖率上报地址"
        echo "  - 启动时直接运行编译生成的二进制文件，无需使用 goc wrapper"
        echo "  - 配置文件位于: $CONFIG_FILE"
        echo "  - API 和 Admin 服务分别独立运行，使用各自的日志文件"
        exit 1
        ;;
esac

exit 0
