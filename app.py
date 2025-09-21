from flask import Flask, render_template, request, jsonify
import subprocess
import os
import json

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

@app.route('/ethernet_status')
def get_ethernet_status():
    """获取有线网络状态"""
    try:
        # 获取所有设备状态
        code, out, err = run_cmd("nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status")
        if code != 0:
            return jsonify({"error": "无法获取设备状态"})

        ethernet_info = {
            "interface": "未检测到",
            "state": "未知",
            "ip": "无",
            "connection_name": ""
        }

        # 查找有线网卡（类型为 ethernet 且不是未托管）
        for line in out.splitlines():
            parts = line.split(":")
            if len(parts) >= 4 and parts[1] == "ethernet" and parts[2] != "unmanaged":
                interface = parts[0]
                state = parts[2]
                connection_name = parts[3]

                # 获取 IP 地址
                ip = "无"
                if state == "connected":
                    code_ip, out_ip, err_ip = run_cmd(f"nmcli -t -f IP4.ADDRESS device show {interface} 2>/dev/null")
                    if code_ip == 0 and out_ip.strip():
                        ip_list = out_ip.strip().split('\n')
                        ip = ip_list[0].split(':')[1] if ':' in ip_list[0] else ip_list[0]

                ethernet_info = {
                    "interface": interface,
                    "state": state,
                    "ip": ip,
                    "connection_name": connection_name
                }
                break  # 取第一个有线网卡

        return jsonify(ethernet_info)

    except Exception as e:
        return jsonify({"error": str(e)})

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
