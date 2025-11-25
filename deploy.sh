#!/bin/bash
# ===========================================
# 运输费用预测系统 - Linux一键部署脚本
# ===========================================
# 使用方法：
# 1. 将整个项目文件夹上传到服务器
# 2. cd 到项目目录
# 3. chmod +x deploy.sh
# 4. sudo ./deploy.sh
# ===========================================

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}   运输费用预测系统 - 一键部署脚本${NC}"
echo -e "${GREEN}=========================================${NC}"

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}请使用 sudo 运行此脚本${NC}"
    exit 1
fi

# 获取当前目录
PROJECT_DIR=$(pwd)
APP_USER=${SUDO_USER:-$(whoami)}

echo -e "${YELLOW}项目目录: ${PROJECT_DIR}${NC}"
echo -e "${YELLOW}运行用户: ${APP_USER}${NC}"

# 1. 更新系统并安装依赖
echo -e "\n${GREEN}[1/6] 安装系统依赖...${NC}"
if command -v apt-get &> /dev/null; then
    apt-get update -qq
    apt-get install -y -qq python3 python3-pip python3-venv
elif command -v yum &> /dev/null; then
    yum install -y -q python3 python3-pip
elif command -v dnf &> /dev/null; then
    dnf install -y -q python3 python3-pip
else
    echo -e "${RED}不支持的系统，请手动安装 Python3${NC}"
    exit 1
fi

# 2. 创建虚拟环境
echo -e "\n${GREEN}[2/6] 创建Python虚拟环境...${NC}"
if [ -d "venv" ]; then
    rm -rf venv
fi
python3 -m venv venv
source venv/bin/activate

# 3. 安装Python依赖
echo -e "\n${GREEN}[3/6] 安装Python依赖...${NC}"
pip install --upgrade pip -q
pip install -r requirements.txt -q
pip install gunicorn -q

# 4. 创建systemd服务
echo -e "\n${GREEN}[4/6] 配置系统服务...${NC}"
cat > /etc/systemd/system/transport-predictor.service << EOF
[Unit]
Description=Transport Cost Predictor Web Service
After=network.target

[Service]
Type=simple
User=${APP_USER}
WorkingDirectory=${PROJECT_DIR}
Environment="PATH=${PROJECT_DIR}/venv/bin"
ExecStart=${PROJECT_DIR}/venv/bin/gunicorn --bind 0.0.0.0:5000 --workers 2 --timeout 120 app:app
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# 5. 设置文件权限
echo -e "\n${GREEN}[5/6] 设置文件权限...${NC}"
chown -R ${APP_USER}:${APP_USER} ${PROJECT_DIR}
chmod -R 755 ${PROJECT_DIR}
chmod 666 ${PROJECT_DIR}/today_data.json 2>/dev/null || touch ${PROJECT_DIR}/today_data.json && chmod 666 ${PROJECT_DIR}/today_data.json

# 6. 启动服务
echo -e "\n${GREEN}[6/6] 启动服务...${NC}"
systemctl daemon-reload
systemctl enable transport-predictor
systemctl restart transport-predictor

# 等待服务启动
sleep 3

# 检查服务状态
if systemctl is-active --quiet transport-predictor; then
    echo -e "\n${GREEN}=========================================${NC}"
    echo -e "${GREEN}✓ 部署成功！${NC}"
    echo -e "${GREEN}=========================================${NC}"
    
    # 获取服务器IP
    SERVER_IP=$(hostname -I | awk '{print $1}')
    
    echo -e "\n访问地址: ${YELLOW}http://${SERVER_IP}:5000${NC}"
    echo -e "\n常用命令:"
    echo -e "  查看状态: ${YELLOW}sudo systemctl status transport-predictor${NC}"
    echo -e "  查看日志: ${YELLOW}sudo journalctl -u transport-predictor -f${NC}"
    echo -e "  重启服务: ${YELLOW}sudo systemctl restart transport-predictor${NC}"
    echo -e "  停止服务: ${YELLOW}sudo systemctl stop transport-predictor${NC}"
else
    echo -e "\n${RED}✗ 服务启动失败，请检查日志：${NC}"
    echo -e "${YELLOW}sudo journalctl -u transport-predictor -n 50${NC}"
    exit 1
fi

# 配置防火墙（如果有）
if command -v firewall-cmd &> /dev/null; then
    echo -e "\n${GREEN}配置防火墙...${NC}"
    firewall-cmd --permanent --add-port=5000/tcp 2>/dev/null || true
    firewall-cmd --reload 2>/dev/null || true
elif command -v ufw &> /dev/null; then
    echo -e "\n${GREEN}配置防火墙...${NC}"
    ufw allow 5000/tcp 2>/dev/null || true
fi

echo -e "\n${GREEN}部署完成！${NC}"

