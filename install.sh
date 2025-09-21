#!/bin/bash

set -e  # 遇错即停

echo "🚀 开始安装 Flask 无线网页管理器..."

# 1. 安装系统依赖
echo "📦 安装系统依赖..."
apt update
apt install -y python3 python3-pip git vnstat dos2unix

# 2. 安装 Python 依赖
echo "🐍 安装 Python 依赖..."
pip3 install -r requirements.txt

# 3. 修复换行符（防止 ^M 错误）
echo "🔧 修复脚本换行符..."
dos2unix *.sh 2>/dev/null || echo "dos2unix 未安装或无需修复"

# 4. 安装到 /opt/wifi-manager
echo "📂 安装到 /opt/wifi-manager..."
INSTALL_DIR="/opt/wifi-manager"
mkdir -p "$INSTALL_DIR"
cp -r ./* "$INSTALL_DIR/"

# 5. 复制并启用系统服务
echo "🔁 设置开机自启服务..."
cp "$INSTALL_DIR/systemd/wifi-manager.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable wifi-manager.service
systemctl restart wifi-manager.service

# 6. 显示访问地址
IP=$(hostname -I | awk '{print $1}')
echo ""
echo "✅ 安装完成！"
echo "🌐 请访问: http://$IP:9576"
echo "📜 服务名: wifi-manager.service"
echo "   启动: sudo systemctl start wifi-manager"
echo "   停止: sudo systemctl stop wifi-manager"
echo "   日志: journalctl -u wifi-manager -f"
