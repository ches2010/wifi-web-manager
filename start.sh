#!/bin/bash

# 修复换行符（开发机可能从 Windows 传来）
dos2unix *.sh 2>/dev/null || true

# 启动 Flask 应用
echo "🚀 启动 Flask 无线管理器 (http://0.0.0.0:9576)"
python3 app.py
