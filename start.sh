#!/bin/bash
# 快速启动脚本（开发/测试用）
# 使用方法: ./start.sh

set -e

echo "🚀 启动运输费用预测系统..."

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

# 启动应用
echo "✅ 启动服务..."
echo "访问地址: http://localhost:3000"
python app.py

