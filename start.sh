#!/bin/bash
# 运输费用预测系统 - 服务管理脚本
# 使用方法: 
#   ./start.sh          启动服务
#   ./start.sh start    启动服务
#   ./start.sh stop     停止服务
#   ./start.sh restart  重启服务
#   ./start.sh status   查看状态
#   ./start.sh logs     查看日志

set -e

PROJECT_DIR=$(cd "$(dirname "$0")" && pwd)
LOG_FILE="$PROJECT_DIR/app.log"
PID_FILE="$PROJECT_DIR/app.pid"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 获取服务状态
get_status() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            echo "running"
            return 0
        fi
    fi
    echo "stopped"
    return 1
}

# 启动服务
do_start() {
    echo -e "${GREEN}🚀 启动运输费用预测系统...${NC}"
    
    # 检查是否已经在运行
    if [ "$(get_status)" = "running" ]; then
        PID=$(cat "$PID_FILE")
        echo -e "${YELLOW}⚠️  服务已在运行 (PID: $PID)${NC}"
        echo "如需重启，请运行: $0 restart"
        return 1
    fi
    
    # 清理旧的 PID 文件
    rm -f "$PID_FILE"
    
    # 检查虚拟环境
    if [ ! -d "$PROJECT_DIR/venv" ]; then
        echo -e "${YELLOW}📦 创建虚拟环境...${NC}"
        python3 -m venv "$PROJECT_DIR/venv"
    fi
    
    # 激活虚拟环境
    source "$PROJECT_DIR/venv/bin/activate"
    
    # 安装依赖
    echo "📥 检查依赖..."
    pip install -r "$PROJECT_DIR/requirements.txt" -q
    
    # 后台启动应用
    echo "✅ 启动服务（后台运行）..."
    cd "$PROJECT_DIR"
    nohup python app.py > "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    
    sleep 2
    
    # 检查是否启动成功
    if [ "$(get_status)" = "running" ]; then
        PID=$(cat "$PID_FILE")
        echo -e "${GREEN}=========================================${NC}"
        echo -e "${GREEN}✅ 服务启动成功！${NC}"
        echo -e "${GREEN}=========================================${NC}"
        echo -e "访问地址: ${YELLOW}http://localhost:3000${NC}"
        echo -e "进程 PID: ${YELLOW}$PID${NC}"
        echo -e "日志文件: ${YELLOW}$LOG_FILE${NC}"
        echo ""
        echo "常用命令:"
        echo -e "  查看日志: ${YELLOW}$0 logs${NC}"
        echo -e "  重启服务: ${YELLOW}$0 restart${NC}"
        echo -e "  停止服务: ${YELLOW}$0 stop${NC}"
    else
        echo -e "${RED}❌ 启动失败，请查看日志:${NC}"
        tail -20 "$LOG_FILE"
        return 1
    fi
}

# 停止服务
do_stop() {
    echo -e "${YELLOW}🛑 停止服务...${NC}"
    
    if [ "$(get_status)" = "stopped" ]; then
        echo "服务未在运行"
        rm -f "$PID_FILE"
        return 0
    fi
    
    PID=$(cat "$PID_FILE")
    echo "正在停止进程 $PID..."
    
    # 先尝试优雅停止
    kill "$PID" 2>/dev/null || true
    
    # 等待进程结束
    for i in {1..10}; do
        if ! kill -0 "$PID" 2>/dev/null; then
            break
        fi
        sleep 1
    done
    
    # 如果还在运行，强制杀死
    if kill -0 "$PID" 2>/dev/null; then
        echo "强制停止..."
        kill -9 "$PID" 2>/dev/null || true
    fi
    
    rm -f "$PID_FILE"
    echo -e "${GREEN}✅ 服务已停止${NC}"
}

# 重启服务
do_restart() {
    echo -e "${GREEN}🔄 重启服务...${NC}"
    do_stop
    sleep 1
    do_start
}

# 查看状态
do_status() {
    if [ "$(get_status)" = "running" ]; then
        PID=$(cat "$PID_FILE")
        echo -e "${GREEN}✅ 服务运行中 (PID: $PID)${NC}"
        echo -e "访问地址: http://localhost:3000"
    else
        echo -e "${RED}❌ 服务未运行${NC}"
    fi
}

# 查看日志
do_logs() {
    if [ -f "$LOG_FILE" ]; then
        echo -e "${YELLOW}📋 查看日志 (Ctrl+C 退出)${NC}"
        tail -f "$LOG_FILE"
    else
        echo "日志文件不存在"
    fi
}

# 主入口
case "${1:-start}" in
    start)
        do_start
        ;;
    stop)
        do_stop
        ;;
    restart)
        do_restart
        ;;
    status)
        do_status
        ;;
    logs)
        do_logs
        ;;
    *)
        echo "使用方法: $0 {start|stop|restart|status|logs}"
        exit 1
        ;;
esac
