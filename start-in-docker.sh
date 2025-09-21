#!/bin/bash

echo "🔄 初始化 vnstat 数据库..."
# 自动检测活跃网卡并初始化 vnstat
IFACE=$(nmcli -t -f DEVICE,TYPE,STATE device status | grep ethernet | grep connected | head -1 | cut -d: -f1)
if [ -n "$IFACE" ]; then
    echo "📡 检测到网卡: $IFACE"
    vnstat -u -i "$IFACE" 2>/dev/null || echo "vnstat 初始化失败（可能已存在）"
else
    echo "⚠️ 未检测到活跃有线网卡，使用 eth0 作为默认"
    vnstat -u -i eth0 2>/dev/null || echo "vnstat 初始化失败"
fi

echo "🚀 启动 vnstat 后台服务..."
service vnstat start

echo "🌐 启动 Flask 网络管理器..."
python3 app.py
