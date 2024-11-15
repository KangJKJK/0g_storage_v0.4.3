#!/bin/bash

# 컬러 정의
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export NC='\033[0m'  # No Color

# 함수: 명령어 실행 및 결과 확인, 오류 발생 시 사용자에게 계속 진행할지 묻기
execute_with_prompt() {
    local message="$1"
    local command="$2"
    echo -e "${YELLOW}${message}${NC}"
    echo "Executing: $command"
    
    # 명령어 실행 및 오류 내용 캡처
    output=$(eval "$command" 2>&1)
    exit_code=$?

    # 출력 결과를 화면에 표시
    echo "$output"

    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}Error: Command failed: $command${NC}" >&2
        echo -e "${RED}Detailed Error Message:${NC}"
        echo "$output" | sed 's/^/  /'  # 상세 오류 메시지를 들여쓰기하여 출력
        echo

        # 사용자에게 계속 진행할지 묻기
        read -p "오류가 발생했습니다. 계속 진행하시겠습니까? (Y/N): " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo -e "${RED}스크립트를 종료합니다.${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}Success: Command completed successfully.${NC}"
    fi
}

# 서비스 시작 완료를 기다리는 함수
wait_for_service() {
    local service_name=$1
    local max_attempts=10
    local attempt=0
    
    echo "서비스 ${service_name}의 시작을 기다리는 중..."

    while [ $attempt -lt $max_attempts ]; do
        if systemctl is-active --quiet $service_name; then
            echo "서비스 ${service_name}이 정상적으로 시작되었습니다."
            return 0
        fi

        echo "서비스 ${service_name}이 아직 시작되지 않았습니다. ${attempt}초 대기 중..."
        sleep 5
        attempt=$((attempt + 1))
    done

    echo "서비스 ${service_name}이 ${max_attempts}초 내에 시작되지 않았습니다."
    return 1
}

# zgs 서비스 중지 (오류가 나더라도 무시)
stop_zgs_service() {
    echo -e "${GREEN}zgs 서비스 중지 중...${NC}"
    sudo systemctl stop zgs || true
}

# 서비스가 중지된 후 다음 작업 수행
check_and_stop_service

# 1. 패키지 업데이트 및 필수 패키지 설치
execute_with_prompt "패키지 업데이트 중..." "sudo apt-get update"
read -p "설치하려는 패키지들에 대한 권한을 부여하려면 Enter를 누르세요..."
execute_with_prompt "필수 패키지 설치 중..." "sudo apt-get install -y clang cmake build-essential"
execute_with_prompt "git 설치 중..." "sudo apt update && sudo apt install git -y"
execute_with_prompt "stdbuf 설치 중..." "sudo apt-get install coreutils -y"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# 2. Go 설치
if ! command -v go &> /dev/null; then
    execute_with_prompt "Go 다운로드 중..." "wget https://go.dev/dl/go1.22.0.linux-amd64.tar.gz"
    execute_with_prompt "Go 설치 후, 경로 추가 중..." "rm -rf /usr/local/go && tar -C /usr/local -xzf go1.22.0.linux-amd64.tar.gz"
    export PATH=$PATH:/usr/local/go/bin
    echo "PATH=$PATH"  # 경로가 제대로 추가되었는지 확인
else
    echo -e "${GREEN}Go가 이미 설치되어 있습니다.${NC}"
fi
sleep 2

# 3. Rust 설치
execute_with_prompt "Rust 설치 확인 중..." "
if command -v rustc >/dev/null 2>&1; then
    echo 'Rust가 이미 설치되어 있습니다. 버전:'
    rustc --version
else
    echo 'Rust를 설치합니다...'
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi
"

# 4. 0g-storage-node 디렉토리 제거 및 리포지토리 클론
if [ -d "$HOME/0g-storage-node" ]; then
    echo -e "${YELLOW}디렉토리 $HOME/0g-storage-node 가 이미 존재합니다. 삭제 중...${NC}"
    execute_with_prompt "기존 0g-storage-node 디렉토리 제거 중..." "sudo rm -rf $HOME/0g-storage-node"
fi

execute_with_prompt "0g-storage-node 리포지토리 클론 중..." "git clone -b v0.7.3 https://github.com/0glabs/0g-storage-node.git"

# 0g-storage-node 디렉토리로 이동
echo -e "${YELLOW}디렉토리 이동 시도 중...${NC}"
cd $HOME/0g-storage-node || { echo -e "${RED}디렉토리 이동 실패${NC}"; exit 1; }
echo -e "${YELLOW}현재 디렉토리: $(pwd)${NC}"

# 이후 명령어 실행
execute_with_prompt "특정 커밋 체크아웃 중..." "git stash && git fetch --all --tags && git checkout 052d2d7"
execute_with_prompt "git 서브모듈 초기화 중..." "git submodule update --init"

# Cargo 설치
execute_with_prompt "Cargo 삭제 중..." "sudo apt-get remove --purge -y cargo"
execute_with_prompt "Cargo 설치 중..." "sudo apt install -y cargo"
sudo apt update
sudo apt install pkg-config
sudo apt install libssl-dev
sudo rustup update
sudo cargo clean

# Cargo 빌드
if [ "$(pwd)" != "$HOME/0g-storage-node" ]; then
    echo -e "${RED}오류: 현재 디렉토리가 $HOME/0g-storage-node가 아닙니다.${NC}"
    exit 1
fi
execute_with_prompt "Cargo 빌드 중...시간이 오래 걸립니다" "sudo cargo build --release"
echo -e "${GREEN}0g-storage-node 빌드 완료.${NC}"
sleep 2

# 6. 프로필 변경

# 프로파일 변수 업데이트
execute_with_prompt "config파일 삭제 중..." "sudo rm -rf $HOME/0g-storage-node/run/config.toml"
execute_with_prompt "config파일 다운 중..." "sudo curl -o $HOME/0g-storage-node/run/config.toml https://raw.githubusercontent.com/z8000kr/0g-storage-node/main/run/config.toml"

# config.toml 파일 수정
echo -e "${GREEN}config파일 수정 중...${NC}"

# config 파일 경로 정의
CONFIG_FILE="$HOME/0g-storage-node/run/config.toml"

# 파일 권한 설정
chmod u+rw $CONFIG_FILE

# 네트워크 부트 노드 업데이트
update_network_boot_nodes() {
    # 기존 네트워크 부트 노드가 있는지 확인하고, 있으면 제거합니다.
    sed -i '/network_boot_nodes = \[/d' $CONFIG_FILE
    sed -i '/# configured as well to enable UDP discovery./a network_boot_nodes = ["/ip4/54.219.26.22/udp/1234/p2p/16Uiu2HAmTVDGNhkHD98zDnJxQWu3i1FL1aFYeh9"]' $CONFIG_FILE
}

# 사용자에게 RPC 엔드포인트를 선택하도록 요청하는 함수
select_rpc_endpoint() {
    echo "다음 중 하나의 RPC 엔드포인트를 선택하세요:"
    echo "1) https://evmrpc-testnet.0g.ai/"
    echo "2) https://0g-evm-vps.zstake.xyz/"
    echo "3) https://evm-rpc-0gchain.josephtran.xyz/"

    read -p "선택 (1/2/3): " RPC_CHOICE

    case $RPC_CHOICE in
        1) RPC_URL="https://evmrpc-testnet.0g.ai/" ;;
        2) RPC_URL="https://0g-evm-vps.zstake.xyz/" ;;
        3) RPC_URL="https://evm-rpc-0gchain.josephtran.xyz/" ;;
        *) echo "잘못된 선택입니다. 다시 시도하세요." && select_rpc_endpoint ;;
    esac

    # 기존 RPC 설정이 있는지 확인하고, 있으면 제거합니다.
    sed -i '/blockchain_rpc_endpoint = /d' $CONFIG_FILE
    # blockchain_rpc_endpoint 업데이트
    sed -i "/# RPC endpoint to sync event logs on EVM compatible blockchain./a blockchain_rpc_endpoint = \"$RPC_URL\"" $CONFIG_FILE

    echo "RPC 엔드포인트가 $RPC_URL으로 설정되었습니다."
}

# 계약 주소 및 기타 설정 업데이트
update_settings() {
    # 기존 설정이 있는지 확인하고, 있으면 제거합니다.
    sed -i '/log_contract_address = /d' $CONFIG_FILE
    sed -i '/log_sync_start_block_number = /d' $CONFIG_FILE
    sed -i '/confirmation_block_count = /d' $CONFIG_FILE
    sed -i '/mine_contract_address = /d' $CONFIG_FILE
    sed -i '/auto_sync_enabled = /d' $CONFIG_FILE
    sed -i '/reward_contract_address = /d' $CONFIG_FILE

    # 새로운 설정 추가
    sed -i '/# Flow contract address to sync event logs./a log_contract_address = "0xbD2C3F0E65eDF5582141C35969d66e34629cC768"' $CONFIG_FILE
    sed -i '/# the block number when flow contract deployed./a log_sync_start_block_number = 595059' $CONFIG_FILE
    sed -i '/# Number of blocks to confirm a transaction./a confirmation_block_count = 6' $CONFIG_FILE
    sed -i '/# Mine contract address for incentive./a mine_contract_address = "0x6815F41019255e00D6F34aAB8397a6Af5b6D806f"' $CONFIG_FILE
    sed -i '/# all files, and sufficient disk space is required./a auto_sync_enabled = true' $CONFIG_FILE
    sed -i '/# shard_position = "0\/2"/a reward_contract_address = "0x51998C4d486F406a788B766d93510980ae1f9360"' $CONFIG_FILE
}

# miner_key를 config 파일에 업데이트하는 함수
update_miner_key() {
    echo -e "${GREEN}메타마스크 프라이빗키를 입력하세요:${NC}"
    read -p ": " MINER_KEY

    # miner_key 값을 사용자가 입력한 값으로 업데이트
    sed -i "s|^miner_key = \".*\"|miner_key = \"$MINER_KEY\"|" $CONFIG_FILE
}

# RPC 엔드포인트 선택 함수 실행
select_rpc_endpoint

# 업데이트 함수 실행
update_miner_key

echo -e "${GREEN}프라이빗키와 RPC 엔드포인트가 업데이트 되었습니다.${NC}"

# 프로필 업데이트
execute_with_prompt "프로필 업데이트 중..." "source ~/.profile"

# 7. zgs.service 파일 생성

execute_with_prompt "zgs.service 파일 생성 중..." "sudo tee /etc/systemd/system/zgs.service > /dev/null <<EOF
[Unit]
Description=ZGS Node
After=network.target

[Service]
User=$USER
WorkingDirectory=$HOME/0g-storage-node/run
ExecStart=$HOME/0g-storage-node/target/release/zgs_node --config $HOME/0g-storage-node/run/config.toml
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF"

# 8. UFW 설치 및 포트 개방
execute_with_prompt "UFW 설치 중..." "sudo apt-get install -y ufw"
read -p "UFW를 설치한 후 계속하려면 Enter를 누르세요..."
execute_with_prompt "UFW 활성화 중...반응이 없으면 엔터를 누르세요." "sudo ufw enable"
execute_with_prompt "필요한 포트 개방 중..." \
    "sudo ufw allow ssh && \
     sudo ufw allow 26658/tcp && \
     sudo ufw allow 26656/tcp && \
     sudo ufw allow 6060/tcp && \
     sudo ufw allow 1317/tcp && \
     sudo ufw allow 9090/tcp && \
     sudo ufw allow 8545/tcp && \
     sudo ufw allow 9091/tcp"
sleep 2

# 9. Systemd 서비스 재로드 및 zgs 서비스 시작
execute_with_prompt "Systemd 서비스 재로드 중..." "sudo systemctl daemon-reload"
execute_with_prompt "zgs 서비스 활성화 중..." "sudo systemctl enable zgs"
execute_with_prompt "zgs 서비스 시작 중..." "sudo systemctl start zgs"
sleep 5

echo -e "${GREEN}모든 작업이 완료되었습니다. 컨트롤+A+D로 스크린을 분리해주세요.${NC}"
echo -e "${RED}https://faucet.0g.ai/ 에서 반드시 포셋을 받아주세요.${NC}"
echo -e "${RED}다음 명령어로 로그를 확인하세요. tail -f ~/0g-storage-node/run/log/zgs.log.\$\(TZ=UTC date +%Y-%m-%d\) ${NC}"
echo -e "${GREEN}스크립트작성자-https://t.me/kjkresearch${NC}"
