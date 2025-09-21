# 使用轻量基础镜像
FROM ubuntu:20.04

# 设置环境变量，避免交互式安装问题
ENV DEBIAN_FRONTEND=noninteractive

# 安装系统依赖
RUN apt-get update && \
    apt-get install -y \
        python3 \
        python3-pip \
        vnstat \
        network-manager \
        dos2unix \
        net-tools \
        iproute2 \
        curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 安装 Python 依赖
COPY requirements.txt /app/
RUN pip3 install --no-cache-dir -r /app/requirements.txt

# 复制项目文件
WORKDIR /app
COPY . /app/

# 修复脚本换行符（兼容 Windows 编辑）
RUN dos2unix *.sh 2>/dev/null || echo "dos2unix skipped"

# 暴露端口（Flask 默认 5000）
EXPOSE 5000

# 启动脚本
COPY start-in-docker.sh /app/start-in-docker.sh
RUN chmod +x /app/start-in-docker.sh

# 启动命令
CMD ["/app/start-in-docker.sh"]
