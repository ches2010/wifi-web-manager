#!/bin/bash

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== 安装无线网络网页管理器 ===${NC}"

# 切换到用户主目录（假设你已创建 nas 用户，如未创建请先创建）
cd ~

# 创建项目目录
mkdir -p wifi-manager
cd wifi-manager

# 创建虚拟环境（推荐）
python3 -m venv venv
source venv/bin/activate

# 升级 pip
pip install --upgrade pip

# 安装 Flask
pip install Flask

echo -e "${GREEN}✅ Flask 安装完成${NC}"

# 创建 app.py
cat > app.py << 'EOF'
from flask import Flask, render_template, request, jsonify
import subprocess
import os

app = Flask(__name__)

WIFI_INTERFACE = "wlan0"  # 请根据 nmcli device status 修改为你的无线网卡名

def run_cmd(cmd):
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
        return result.returncode, result.stdout.strip(), result.stderr.strip()
    except subprocess.TimeoutExpired:
        return -1, "", "命令超时"

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/status')
def get_status():
    code, out, err = run_cmd(f"nmcli -t -f DEVICE,STATE device status | grep {WIFI_INTERFACE}")
    if code != 0 or not out:
        return jsonify({"error": "无法获取网卡状态"})
    
    parts = out.split(":")
    state = parts[1] if len(parts) > 1 else "未知"
    
    # 获取当前连接的 SSID
    code2, out2, err2 = run_cmd(f"nmcli -t -f active,ssid dev wifi | grep '^yes'")
    current_ssid = out2.split(":")[1] if code2 == 0 and out2 else "未连接"
    
    return jsonify({
        "interface": WIFI_INTERFACE,
        "state": state,
        "current_ssid": current_ssid
    })

@app.route('/scan')
def scan_wifi():
    code, out, err = run_cmd(f"nmcli -t -f ssid,signal,security dev wifi list ifname {WIFI_INTERFACE}")
    if code != 0:
        return jsonify({"error": "扫描失败", "detail": err})
    
    networks = []
    for line in out.splitlines():
        if not line.strip() or line.startswith("::") or "ssid" in line.lower():
            continue
        parts = line.split(":")
        if len(parts) >= 3:
            ssid = parts[0]
            signal = parts[1]
            security = parts[2]
            if ssid:  # 忽略空SSID
                networks.append({
                    "ssid": ssid,
                    "signal": signal,
                    "security": security
                })
    return jsonify(networks)

@app.route('/connect', methods=['POST'])
def connect_wifi():
    data = request.json
    ssid = data.get('ssid')
    password = data.get('password', '')
    
    if not ssid:
        return jsonify({"error": "SSID 不能为空"})
    
    # 先删除旧连接（避免冲突）
    run_cmd(f"nmcli con delete '{ssid}' 2>/dev/null || true")
    
    # 创建并激活连接
    if password:
        cmd = f"nmcli dev wifi connect '{ssid}' password '{password}' ifname {WIFI_INTERFACE}"
    else:
        cmd = f"nmcli dev wifi connect '{ssid}' ifname {WIFI_INTERFACE}"
    
    code, out, err = run_cmd(cmd)
    if code == 0:
        return jsonify({"success": True, "message": "连接成功"})
    else:
        return jsonify({"error": "连接失败", "detail": err})

@app.route('/hotspot', methods=['POST'])
def toggle_hotspot():
    action = request.json.get('action')  # 'start' or 'stop'
    
    if action == 'start':
        ssid = request.json.get('ssid', 'HiNAS-Hotspot')
        password = request.json.get('password', '12345678')
        
        if len(password) < 8:
            return jsonify({"error": "密码至少8位"})
        
        # 停止可能存在的旧热点
        run_cmd("nmcli con down id Hotspot 2>/dev/null || true")
        run_cmd("nmcli con delete Hotspot 2>/dev/null || true")
        
        # 创建并启动热点
        cmd = f"""
        nmcli con add type wifi ifname {WIFI_INTERFACE} con-name Hotspot autoconnect yes ssid "{ssid}"
        nmcli con modify Hotspot 802-11-wireless.mode ap 802-11-wireless.band bg
        nmcli con modify Hotspot 802-11-wireless-security.key-mgmt wpa-psk
        nmcli con modify Hotspot 802-11-wireless-security.psk "{password}"
        nmcli con modify Hotspot ipv4.method shared
        nmcli con up Hotspot
        """
        code, out, err = run_cmd(cmd)
        if code == 0:
            return jsonify({"success": True, "message": "热点已启动"})
        else:
            return jsonify({"error": "热点启动失败", "detail": err})
    
    elif action == 'stop':
        code, out, err = run_cmd("nmcli con down id Hotspot")
        if code == 0:
            return jsonify({"success": True, "message": "热点已关闭"})
        else:
            return jsonify({"error": "热点关闭失败", "detail": err})
    
    else:
        return jsonify({"error": "无效操作"})

@app.route('/toggle', methods=['POST'])
def toggle_wifi():
    action = request.json.get('action')  # 'on' or 'off'
    if action == 'on':
        code, out, err = run_cmd(f"nmcli radio wifi on")
        if code == 0:
            return jsonify({"success": True, "message": "无线已开启"})
        else:
            return jsonify({"error": "开启失败", "detail": err})
    elif action == 'off':
        code, out, err = run_cmd(f"nmcli radio wifi off")
        if code == 0:
            return jsonify({"success": True, "message": "无线已关闭"})
        else:
            return jsonify({"error": "关闭失败", "detail": err})
    else:
        return jsonify({"error": "无效操作"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=9576, debug=False)
EOF

echo -e "${GREEN}✅ app.py 创建完成${NC}"

# 创建 templates 目录和前端页面
mkdir -p templates

cat > templates/index.html << 'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>无线网络管理器 - HiNAS</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        .card { margin-bottom: 20px; }
        .btn { margin: 5px; }
        .hidden { display: none; }
        pre { background: #f8f9fa; padding: 10px; border-radius: 5px; }
    </style>
</head>
<body class="bg-light">
    <div class="container py-4">
        <h1 class="mb-4">📶 无线网络管理器</h1>

        <div class="card">
            <div class="card-header">当前状态</div>
            <div class="card-body">
                <div id="status">加载中...</div>
                <button class="btn btn-outline-primary" onclick="refreshStatus()">🔄 刷新状态</button>
                <button class="btn btn-outline-success" onclick="toggleWifi('on')">✅ 开启无线</button>
                <button class="btn btn-outline-danger" onclick="toggleWifi('off')">⛔ 关闭无线</button>
            </div>
        </div>

        <div class="card">
            <div class="card-header">扫描附近网络</div>
            <div class="card-body">
                <button class="btn btn-primary" onclick="scanWifi()">🔍 扫描 Wi-Fi</button>
                <div id="scanResults" class="mt-3"></div>
            </div>
        </div>

        <div class="card">
            <div class="card-header">连接 Wi-Fi</div>
            <div class="card-body">
                <input type="text" id="connectSsid" class="form-control mb-2" placeholder="输入 SSID">
                <input type="password" id="connectPassword" class="form-control mb-2" placeholder="密码（如无密码可留空）">
                <button class="btn btn-success" onclick="connectWifi()">🔌 连接</button>
                <div id="connectResult" class="mt-2"></div>
            </div>
        </div>

        <div class="card">
            <div class="card-header">创建热点</div>
            <div class="card-body">
                <input type="text" id="hotspotSsid" class="form-control mb-2" placeholder="热点名称" value="HiNAS-Hotspot">
                <input type="password" id="hotspotPassword" class="form-control mb-2" placeholder="热点密码（至少8位）" value="12345678">
                <button class="btn btn-warning" onclick="startHotspot()">📡 启动热点</button>
                <button class="btn btn-secondary" onclick="stopHotspot()">🛑 停止热点</button>
                <div id="hotspotResult" class="mt-2"></div>
            </div>
        </div>

    </div>

    <script>
        async function apiCall(url, data = null) {
            const options = {
                method: data ? 'POST' : 'GET',
                headers: { 'Content-Type': 'application/json' }
            };
            if (data) options.body = JSON.stringify(data);
            const res = await fetch(url, options);
            return await res.json();
        }

        async function refreshStatus() {
            const data = await apiCall('/status');
            if (data.error) {
                document.getElementById('status').innerHTML = `<div class="alert alert-danger">${data.error}</div>`;
            } else {
                document.getElementById('status').innerHTML = `
                    <p><strong>网卡：</strong> ${data.interface}</p>
                    <p><strong>状态：</strong> ${data.state}</p>
                    <p><strong>当前连接：</strong> ${data.current_ssid}</p>
                `;
            }
        }

        async function toggleWifi(action) {
            const data = await apiCall('/toggle', { action });
            alert(data.error || data.message);
            refreshStatus();
        }

        async function scanWifi() {
            const data = await apiCall('/scan');
            if (data.error) {
                document.getElementById('scanResults').innerHTML = `<div class="alert alert-danger">${data.error}</div>`;
                return;
            }
            let html = '<div class="list-group">';
            data.forEach(net => {
                html += `
                    <div class="list-group-item d-flex justify-content-between align-items-center">
                        <div>
                            <strong>${net.ssid}</strong><br>
                            <small>信号: ${net.signal}% | 安全: ${net.security}</small>
                        </div>
                        <button class="btn btn-sm btn-outline-primary" onclick="quickConnect('${net.ssid}')">连接</button>
                    </div>
                `;
            });
            html += '</div>';
            document.getElementById('scanResults').innerHTML = html;
        }

        function quickConnect(ssid) {
            document.getElementById('connectSsid').value = ssid;
        }

        async function connectWifi() {
            const ssid = document.getElementById('connectSsid').value;
            const password = document.getElementById('connectPassword').value;
            if (!ssid) {
                alert('请输入 SSID');
                return;
            }
            const data = await apiCall('/connect', { ssid, password });
            document.getElementById('connectResult').innerHTML = `
                <div class="alert alert-${data.error ? 'danger' : 'success'}">
                    ${data.error || data.message}
                </div>
            `;
            refreshStatus();
        }

        async function startHotspot() {
            const ssid = document.getElementById('hotspotSsid').value;
            const password = document.getElementById('hotspotPassword').value;
            if (!ssid) {
                alert('请输入热点名称');
                return;
            }
            const data = await apiCall('/hotspot', { action: 'start', ssid, password });
            document.getElementById('hotspotResult').innerHTML = `
                <div class="alert alert-${data.error ? 'danger' : 'success'}">
                    ${data.error || data.message}
                </div>
            `;
            refreshStatus();
        }

        async function stopHotspot() {
            const data = await apiCall('/hotspot', { action: 'stop' });
            document.getElementById('hotspotResult').innerHTML = `
                <div class="alert alert-${data.error ? 'danger' : 'success'}">
                    ${data.error || data.message}
                </div>
            `;
            refreshStatus();
        }

        // 页面加载时自动刷新状态
        document.addEventListener('DOMContentLoaded', refreshStatus);
    </script>
</body>
</html>
EOF

echo -e "${GREEN}✅ 前端页面创建完成${NC}"

# 创建启动脚本
cat > start.sh << 'EOF'
#!/bin/bash
source venv/bin/activate
python app.py
EOF

chmod +x start.sh

echo -e "${GREEN}✅ 启动脚本创建完成${NC}"

# 提示用户
echo ""
echo -e "${YELLOW}🎉 安装完成！${NC}"
echo ""
echo -e "${GREEN}请运行以下命令启动服务：${NC}"
echo ""
echo -e "    cd ~/wifi-manager && ./start.sh"
echo ""
echo -e "${YELLOW}然后在浏览器访问：http://<你的服务器IP>:9576${NC}"
echo ""
echo -e "${YELLOW}建议设置开机自启（见下方说明）${NC}"
