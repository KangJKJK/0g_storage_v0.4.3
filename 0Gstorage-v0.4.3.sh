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

# 1. 패키지 업데이트 및 필수 패키지 설치
execute_with_prompt "패키지 업데이트 중..." "sudo apt-get update"
read -p "설치하려는 패키지들에 대한 권한을 부여하려면 Enter를 누르세요..."
execute_with_prompt "필수 패키지 설치 중..." "sudo apt-get install -y clang cmake build-essential"
sleep 2

# 2. Go 설치
execute_with_prompt "Go 다운로드 중..." "wget https://go.dev/dl/go1.22.0.linux-amd64.tar.gz"
sleep 2

execute_with_prompt "Go 설치 후, 경로 추가 중..." "sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.22.0.linux-amd64.tar.gz"
export PATH=$PATH:/usr/local/go/bin
echo "PATH=$PATH"  # 경로가 제대로 추가되었는지 확인
sleep 2

# 3. Rust 설치
if ! command -v rustc &> /dev/null; then
    execute_with_prompt "Rust 설치 중..." \
    "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && rustup update"
    # 환경 변수 설정
    export PATH="$HOME/.cargo/bin:$PATH"
else
    echo -e "${GREEN}Rust가 이미 설치되어 있습니다.${NC}"
fi
sleep 2

# 5. 0g-storage-node 디렉토리 제거 및 리포지토리 클론
execute_with_prompt "기존 0g-storage-node 디렉토리 제거 중..." "sudo rm -rf $HOME/0g-storage-node"
execute_with_prompt "git 설치 중..." "sudo apt install -y git"
read -p "Git을 설치한 후 계속하려면 Enter를 누르세요..."
execute_with_prompt "0g-storage-node 리포지토리 클론 중..." "git clone -b v0.4.3 https://github.com/0glabs/0g-storage-node.git"
execute_with_prompt "특정 커밋 체크아웃 중..." "cd $HOME/0g-storage-node && git stash && git fetch --all --tags && git checkout 2e83484"
execute_with_prompt "git 서브모듈 초기화 중..." "git submodule update --init"
execute_with_prompt "Cargo 설치 중..." "sudo apt install -y cargo"
read -p "Cargo를 설치한 후 계속하려면 Enter를 누르세요..."
echo -e "${YELLOW}0g-storage-node 빌드 중...${NC}"
execute_with_prompt "Cargo 빌드 중..." "cargo build --release"
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

# config.toml 파일 업데이트
sed -i 's|# network_boot_nodes = \[\]|network_boot_nodes = \["/ip4/54.219.26.22/udp/1234/p2p/16Uiu2HAmTVDGNhkHD98zDnJxQWu3i1FL1aFYeh9wiQTNu4pDCgps","/ip4/52.52.127.117/udp/1234/p2p/16Uiu2HAkzRjxK2gorngB1Xq84qDrT4hSVznYDHj6BkbaE4SGx9oS","/ip4/18.162.65.205/udp/1234/p2p/16Uiu2HAm2k6ua2mGgvZ8rTMV8GhpW71aVzkQWy7D37TTDuLCpgmX"\]|' $CONFIG_FILE
sed -i 's|# log_contract_address = ""|log_contract_address = "0xbD2C3F0E65eDF5582141C35969d66e34629cC768"|' $CONFIG_FILE
sed -i 's|# log_sync_start_block_number = 0|log_sync_start_block_number = 595059|' $CONFIG_FILE
sed -i 's|# confirmation_block_count = 12|confirmation_block_count = 6|' $CONFIG_FILE
sed -i 's|# mine_contract_address = ""|mine_contract_address = "0x6815F41019255e00D6F34aAB8397a6Af5b6D806f"|' $CONFIG_FILE
sed -i 's|# shard_position = "0/2"|shard_position = "0/2"\n\nreward_contract_address = "0x51998C4d486F406a788B766d93510980ae1f9360"|' $CONFIG_FILE
sed -i 's|# auto_sync_enabled = false|auto_sync_enabled = true|' $CONFIG_FILE

# 사용자에게 RPC 엔드포인트을 선택하도록 요청하는 함수
select_rpc_endpoint() {
    echo -e "${GREEN}다음 중 하나의 RPC 엔드포인트을 선택하세요:${NC}"
    echo "1) https://evm-rpc-0gchain.josephtran.xyz/"
    echo "2) https://0g-testnet-rpc.tech-coha05.xyz/"
    echo "3) https://lightnode-rpc-0g.grandvalleys.com/"
    
    read -p "선택 (1/2/3): " RPC_CHOICE

    case $RPC_CHOICE in
        1)
            RPC_URL="https://evm-rpc-0gchain.josephtran.xyz/"
            ;;
        2)
            RPC_URL="https://0g-testnet-rpc.tech-coha05.xyz/"
            ;;
        3)
            RPC_URL="https://lightnode-rpc-0g.grandvalleys.com/"
            ;;
        *)
            echo -e "${RED}잘못된 선택입니다. 기본값을 사용합니다.${NC}"
            RPC_URL="https://evm-rpc-0gchain.josephtran.xyz/"
            ;;
    esac

    # Update the blockchain_rpc_endpoint in the config file
    sed -i "s|# blockchain_rpc_endpoint = \"http://127.0.0.1:8545\"|blockchain_rpc_endpoint = \"$RPC_URL\"|" $CONFIG_FILE
}

# miner_key를 config 파일에 업데이트하는 함수
update_miner_key() {
    echo -e "${GREEN}메타마스크 프라이빗키를 입력하세요:${NC}"
    read -p ": " MINER_KEY

    # Update the miner_key in the config file
    sed -i "s|# miner_key = \"\"|miner_key = \"$MINER_KEY\"|" $CONFIG_FILE
}

# RPC 엔드포인트 선택 함수 실행
select_rpc_endpoint

# 업데이트 함수 실행
update_miner_key

echo -e "${GREEN}프라이빗키와 RPC 엔드포인트가 업데이트 되었습니다.${NC}"

# 프로파일 다시 로드
execute_with_prompt "프로필 업데이트중..." "source ~/.bash_profile"

# 7. zgs.service 파일 생성
execute_with_prompt "zgs.service 파일 생성 중..." "sudo tee /etc/systemd/system/zgs.service > /dev/null <<EOF
[Unit]
Description=ZGS Node
After=network.target

[Service]
User=root
WorkingDirectory=\$HOME/0g-storage-node/run
ExecStart=\$HOME/0g-storage-node/target/release/zgs_node --config $HOME/0g-storage-node/run/config.toml
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF"
sleep 2

# 8. UFW 설치 및 포트 개방
execute_with_prompt "UFW 설치 중..." "sudo apt-get install -y ufw"
read -p "UFW를 설치한 후 계속하려면 Enter를 누르세요..."
execute_with_prompt "UFW 활성화 중..." "sudo ufw enable"
execute_with_prompt "필요한 포트 개방 중..." \
    "sudo ufw allow ssh && \
     sudo ufw allow 26658 && \
     sudo ufw allow 26656 && \
     sudo ufw allow 6060 && \
     sudo ufw allow 1317 && \
     sudo ufw allow 9090 && \
     sudo ufw allow 9091"
sleep 2

# 9. Systemd 서비스 재로드 및 zgs 서비스 시작
execute_with_prompt "Systemd 서비스 재로드 중..." "sudo systemctl daemon-reload"
execute_with_prompt "zgs 서비스 활성화 중..." "sudo systemctl enable zgs"
execute_with_prompt "zgs 서비스 시작 중..." "sudo systemctl start zgs"
sleep 2

# 10. 로그 확인
execute_with_prompt "로그 확인 중..." "tail -f ~/0g-storage-node/run/log/zgs.log.$(TZ=UTC date +%Y-%m-%d)"
sleep 2

echo -e "${GREEN}모든 작업이 완료되었습니다. 컨트롤+A+D로 스크린을 분리해주세요.${NC}"
echo -e "${GREEN}스크립트작성자-kangjk${NC}"