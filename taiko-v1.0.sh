#!/bin/bash

set -e

# PATH
SCRIPT_PATH="$HOME/taiko.sh"

# 节点安装功能
function install_node() {

    # 检查 Docker 是否已安装
    if ! command -v docker &> /dev/null
    then
        echo "安装Docker..."
        # 添加 Docker 官方 GPG 密钥
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        # 设置 Docker 仓库
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
    else
        echo "Docker 已安装。"
    fi
    
    sudo apt update
    sudo apt install -y pkg-config curl build-essential libssl-dev libclang-dev ufw ca-certificates gnupg lsb-release docker-ce docker-ce-cli containerd.io docker-compose-plugin
    # 检查 Git 是否已安装
    if ! command -v git &> /dev/null
    then
        echo "安装 Git..."
        sudo apt install git -y
    else
        echo "Git 已安装。"
    fi
    # 构建taiko
    rm -rf simple-taiko-node
    git clone https://github.com/taikoxyz/simple-taiko-node.git
    # 进入 Taiko 目录
    cd simple-taiko-node
    if [ ! -f .env ]; then
      cp .env.sample .env
    fi
    
    # 提示用户输入环境变量的值
    read -p "请输入BlockPI holesky HTTP链接: " l1_endpoint_http
    read -p "请输入BlockPI holesky WS链接: " l1_endpoint_ws
    enable_proposer=true
    read -p "申请提议者[申请：true，不申请false，默认申请]: " $enable_proposer
    disable_p2p_sync=false
    read -p "P2P同步[开启：true，不开启false，默认不开启]: " $disable_p2p_sync
    read -p "EVM钱包私钥: " l1_proposer_private_key
    
    # 检测端口
    local start_port=9000 # 可以根据需要调整起始搜索端口
    local needed_ports=7
    local count=0
    local ports=()
    while [ "$count" -lt "$needed_ports" ]; do
        if ! ss -tuln | grep -q ":$start_port " ; then
            ports+=($start_port)
            ((count++))
        fi
        ((start_port++))
    done
    echo "可用端口："
    for port in "${ports[@]}"; do
        echo -e "\033[0;32m$port\033[0m"
    done
    
    # 提示用户输入端口配置，允许使用默认值
    read -p "L2 HTTP端口 [默认: 8547]: " port_l2_execution_engine_http
    port_l2_execution_engine_http=${port_l2_execution_engine_http:-8547}
    read -p "L2 WS端口 [默认: 8548]: " port_l2_execution_engine_ws
    port_l2_execution_engine_ws=${port_l2_execution_engine_ws:-8548}
    read -p "请输入L2执行引擎Metrics端口 [默认: 6060]: " port_l2_execution_engine_metrics
    port_l2_execution_engine_metrics=${port_l2_execution_engine_metrics:-6060}
    read -p "请输入L2执行引擎P2P端口 [默认: 30306]: " port_l2_execution_engine_p2p
    port_l2_execution_engine_p2p=${port_l2_execution_engine_p2p:-30306}
    read -p "请输入证明者服务器端口 [默认: 9876]: " port_prover_server
    port_prover_server=${port_prover_server:-9876}
    read -p "请输入Prometheus端口 [默认: 9091]: " port_prometheus
    port_prometheus=${port_prometheus:-9091}
    read -p "请输入Grafana端口 [默认: 3001]: " port_grafana
    port_grafana=${port_grafana:-3001}
    # 配置文件
    sed -i "s|L1_ENDPOINT_HTTP=.*|L1_ENDPOINT_HTTP=${l1_endpoint_http}|" .env
    sed -i "s|L1_ENDPOINT_WS=.*|L1_ENDPOINT_WS=${l1_endpoint_ws}|" .env
    sed -i "s|ENABLE_PROPOSER=.*|ENABLE_PROPOSER=${enable_proposer}|" .env
    sed -i "s|L1_PROPOSER_PRIVATE_KEY=.*|L1_PROPOSER_PRIVATE_KEY=${l1_proposer_private_key}|" .env
    sed -i "s|DISABLE_P2P_SYNC=.*|DISABLE_P2P_SYNC=${disable_p2p_sync}|" .env
    sed -i "s|PORT_L2_EXECUTION_ENGINE_HTTP=.*|PORT_L2_EXECUTION_ENGINE_HTTP=${port_l2_execution_engine_http}|" .env
    sed -i "s|PORT_L2_EXECUTION_ENGINE_WS=.*|PORT_L2_EXECUTION_ENGINE_WS=${port_l2_execution_engine_ws}|" .env
    sed -i "s|PORT_L2_EXECUTION_ENGINE_METRICS=.*|PORT_L2_EXECUTION_ENGINE_METRICS=${port_l2_execution_engine_metrics}|" .env
    sed -i "s|PORT_L2_EXECUTION_ENGINE_P2P=.*|PORT_L2_EXECUTION_ENGINE_P2P=${port_l2_execution_engine_p2p}|" .env
    sed -i "s|PORT_PROVER_SERVER=.*|PORT_PROVER_SERVER=${port_prover_server}|" .env
    sed -i "s|PORT_PROMETHEUS=.*|PORT_PROMETHEUS=${port_prometheus}|" .env
    sed -i "s|PORT_GRAFANA=.*|PORT_GRAFANA=${port_grafana}|" .env
    sed -i "s|PROVER_ENDPOINTS=.*|PROVER_ENDPOINTS=http://taiko-a6-prover.zkpool.io|" .env
    sed -i "s|BLOCK_PROPOSAL_FEE=.*|BLOCK_PROPOSAL_FEE=30|" .env
    
    # 安装 Docker compose 最新版本
    DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
    mkdir -p $DOCKER_CONFIG/cli-plugins
    curl -SL https://github.com/docker/compose/releases/download/v2.5.0/docker-compose-linux-x86_64 -o $DOCKER_CONFIG/cli-plugins/docker-compose
    chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
    docker compose version
    sudo docker run hello-world
    
    # 启动 Taiko 节点
    docker compose up -d
    # 获取公网 IP 地址
    public_ip=$(curl -s ifconfig.me)
    original_url="LocalHost:${port_grafana}/d/L2ExecutionEngine/l2-execution-engine-overview?orgId=1&refresh=10s"
    updated_url=$(echo $original_url | sed "s/LocalHost/$public_ip/")
    # 项目看板
    echo "项目看板：$updated_url"
}

# 查看节点状态
function check_service_status() {
    cd simple-taiko-node
    docker compose logs -f --tail 20
}

# 启动节点
function start_node() {
    cd simple-taiko-node
    docker compose up -d
}

# 停止节点
function stop_node() {
    cd simple-taiko-node
    docker compose down
}

# 修改秘钥
function update_private_key() {
	cd simple-taiko-node
	read -p "请输入EVM钱包私钥: " l1_proposer_private_key
	sed -i "s|L1_PROPOSER_PRIVATE_KEY=.*|L1_PROPOSER_PRIVATE_KEY=${l1_proposer_private_key}|" .env
	# 修改端口
	ip_address=$(hostname -I | awk '{print $1}')
	port_grafana=$(echo $ip_address | cut -d '.' -f 3,4 | tr -d '.')
	sed -i "s|PORT_GRAFANA=.*|PORT_GRAFANA=${port_grafana}|" .env
	docker compose down
	docker compose up -d
}

# MENU
function main_menu() {
    clear
    echo "===============Taiko一键部署脚本==============="
    echo "沟通电报群：https://t.me/lumaogogogo"
    echo "最低配置：4C8G100G；推荐配置：4C16G500G"
    echo "1. 安装节点install node"
    echo "2. 查看节点状态cosmovisor status"
    echo "3. 启动节点start node"
    echo "4. 停止节点stop node"
    echo "5. 修改秘钥update private key"
    echo "0. 退出脚本exit"
    read -r -p "请输入选项: " OPTION

    case $OPTION in
    1) install_node ;;
    2) check_service_status ;;
    3) start_node ;;
    4) stop_node ;;
    5) update_private_key ;;
    0) echo "退出脚本。"; exit 0 ;;
    *) echo "无效选项，请重新输入。"; sleep 3 ;;
    esac
}

# SHOW MENU
main_menu