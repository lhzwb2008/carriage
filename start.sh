#!/bin/bash
# 快速启动脚本（开发/测试用）
# 使用方法: ./start.sh

set -e

PROJECT_DIR=$(cd "$(dirname "$0")" && pwd)
LOG_FILE="$PROJECT_DIR/app.log"
PID_FILE="$PROJECT_DIR/app.pid"

echo "🚀 启动运输费用预测系统..."

# 检查是否已经在运行
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "⚠️  服务已在运行 (PID: $OLD_PID)"
        echo "如需重启，请先运行: kill $OLD_PID"
        exit 1
    else
        rm -f "$PID_FILE"
    fi
fi

# 检查虚拟环境
if [ ! -d "venv" ]; then
    echo "📦 创建虚拟环境..."
    python3 -m venv venv
fi

# 激活虚拟环境
source venv/bin/activate

# 安装依赖
echo "📥 检查依赖..."
pip install -r requirements.txt -q

# 后台启动应用
echo "✅ 启动服务（后台运行）..."
nohup python app.py > "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"

sleep 2

# 检查是否启动成功
if kill -0 $(cat "$PID_FILE") 2>/dev/null; then
    echo "========================================="
    echo "✅ 服务启动成功！"
    echo "========================================="
    echo "访问地址: http://localhost:3000"
    echo "进程 PID: $(cat $PID_FILE)"
    echo "日志文件: $LOG_FILE"
    echo ""
    echo "常用命令:"
    echo "  查看日志: tail -f $LOG_FILE"
    echo "  停止服务: kill \$(cat $PID_FILE)"
else
    echo "❌ 启动失败，请查看日志: $LOG_FILE"
    cat "$LOG_FILE"
    exit 1
fi

