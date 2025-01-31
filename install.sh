#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
plain='\033[0m'
NC='\033[0m' 

cur_dir=$(pwd)

[[ $EUID -ne 0 ]] && echo -e "${RED}Fatal error: ${plain} Please run this script with root privilege \n " && exit 1

install_jq() {
    if ! command -v jq &> /dev/null; then
        if command -v apt-get &> /dev/null; then
            echo -e "${RED}jq is not installed. Installing...${NC}"
            sleep 1
            sudo apt-get update
            sudo apt-get install -y jq
        else
            echo -e "${RED}Error: Unsupported package manager. Please install jq manually.${NC}\n"
            read -p "Press any key to continue..."
            exit 1
        fi
    fi
}

install_obfs4() {
    if ! command -v obfs4proxy &> /dev/null; then
        echo -e "${YELLOW}Installing obfs4proxy...${NC}"
        sudo apt-get update
        sudo apt-get install -y obfs4proxy
        if ! command -v obfs4proxy &> /dev/null; then
            echo -e "${RED}Failed to install obfs4proxy. Please install it manually.${NC}"
            exit 1
        else
            echo -e "${GREEN}obfs4proxy installed successfully.${NC}"
        fi
    fi
}

configure_obfs4() {
    local obfs4_dir="/etc/obfs4"
    local obfs4_cert="$obfs4_dir/obfs4_cert"
    local obfs4_key="$obfs4_dir/obfs4_key"

    mkdir -p "$obfs4_dir"

    if [ ! -f "$obfs4_cert" ] || [ ! -f "$obfs4_key" ]; then
        echo -e "${YELLOW}Generating obfs4 certificate and private key...${NC}"
        
        openssl genpkey -algorithm RSA -out "$obfs4_key" -pkeyopt rsa_keygen_bits:2048
        if [ $? -ne 0 ]; then
            echo -e "${RED}Failed to generate private key.${NC}"
            exit 1
        fi

        openssl req -new -x509 -key "$obfs4_key" -out "$obfs4_cert" -days 365 -subj "/CN=obfs4"
        if [ $? -ne 0 ]; then
            echo -e "${RED}Failed to generate certificate.${NC}"
            exit 1
        fi

        echo -e "${GREEN}obfs4 certificate and private key generated successfully.${NC}"
    fi

    cat <<EOL > "$obfs4_dir/obfs4.json"
{
    "transport": "obfs4",
    "bind_address": "0.0.0.0:443",
    "cert": "$obfs4_cert",
    "iat-mode": "0",
    "log_level": "INFO",
    "options": {
        "node-id": "$(cat /etc/hostname)",
        "private-key": "$(cat "$obfs4_key")"
    }
}
EOL

    echo -e "${GREEN}obfs4 configuration file created at $obfs4_dir/obfs4.json${NC}"
}

start_obfs4() {
    echo -e "${YELLOW}Starting obfs4 service...${NC}"
    obfs4proxy -logLevel INFO -enableLogging -config /etc/obfs4/obfs4.json &
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}obfs4 service started successfully.${NC}"
    else
        echo -e "${RED}Failed to start obfs4 service.${NC}"
        exit 1
    fi
}

init() {
    install_jq
    install_obfs4
    configure_obfs4
    start_obfs4
    sudo apt-get install -y iproute2 screen
    echo -e "${GREEN}Initialization complete.${NC}"
}

nebula_menu() {
    clear

    # Get server IP
    SERVER_IP=$(hostname -I | awk '{print $1}')

    # Fetch server country using ip-api.com
    SERVER_COUNTRY=$(curl -sS "http://ip-api.com/json/$SERVER_IP" | jq -r '.country')

    # Fetch server isp using ip-api.com 
    SERVER_ISP=$(curl -sS "http://ip-api.com/json/$SERVER_IP" | jq -r '.isp')
	
    nebula_core=$(check_core_status)

    echo "+--------------------------------------------------------------+"
    echo "|                                                              |" 
    echo "|.__   __.  _______ ._____     __    __   __          ___      |"
    echo "||  \ |  | |   ____||   _  \  |  |  |  | |  |        /   \ _   |"
    echo "||  .    | |   __|  |   _  <  |  |  |  | |  |      /  /_\  \   |"
    echo "||  |\   | |  |____ |  |_)  | |   --   | |   ----./  _____  \  |"
    echo "||__| \__| |_______||______/   \______/  |_______/__/     \__\ |"
    echo "|                                                              |" 
    echo "+--------------------------------------------------------------+"    
    echo -e "| Telegram Channel : ${MAGENTA}@AminiDev ${NC}| Version : ${GREEN} 1.0.0${NC} "
    echo "+--------------------------------------------------------------+"  
    echo -e "|${GREEN}Server Country    |${NC} $SERVER_COUNTRY"
    echo -e "|${GREEN}Server IP         |${NC} $SERVER_IP"
    echo -e "|${GREEN}Server ISP        |${NC} $SERVER_ISP"
    echo -e "|${GREEN}Server Tunnel     |${NC} $nebula_core"
    echo "+--------------------------------------------------------------------------------+"
    echo -e "|${YELLOW}Please choose an option:${NC}"
    echo "+--------------------------------------------------------------------------------+"
    echo -e $1
    echo "+---------------------------------------------------------------------------------+"
    echo -e "\033[0m"
}

install_tunnel() {
    nebula_menu "| 1  - IRAN \n| 2  - Kharej \n| 0  - Exit"

    read -p "Enter option number: " setup

    read -p "How many servers: " server_count

    case $setup in
    1)
        for ((i=1;i<=server_count;i++))
        do
            iran_setup $i
        done
        ;;  
    2)
        for ((i=1;i<=server_count;i++))
        do
            kharej_setup $i
        done
        ;;

    0)
        echo -e "${GREEN}Exiting program...${NC}"
        exit 0
        ;;
    *)
        echo "Not valid"
        ;;
    esac
}

iran_setup() {
    echo -e "${YELLOW}Setting up IRAN server $1${NC}"
    
    read -p "Enter IRAN IP    : " iran_ip
    read -p "Enter Kharej IP  : " kharej_ip
    read -p "Enter IPv6 Local : " ipv6_local
    
    cat <<EOL > /etc/netplan/mramini-$1.yaml
network:
  version: 2
  tunnels:
    tunnel0858-$1:
      mode: sit
      local: $iran_ip
      remote: $kharej_ip
      addresses:
        - $ipv6_local::1/64
EOL
    netplan_setup
    sudo netplan apply

    start_obfs4

    cat <<EOL > /root/connectors-$1.sh
ping $ipv6_local::2
EOL

    chmod +x /root/connectors-$1.sh

    screen -dmS connectors_session_$1 bash -c "/root/connectors-$1.sh"

    echo "IRAN Server $1 setup complete."
    echo -e "####################################"
    echo -e "# Your IPv6 :                      #"
    echo -e "#  $ipv6_local::1                  #"
    echo -e "####################################"
}

kharej_setup() {
    echo -e "${YELLOW}Setting up Kharej server $1${NC}"
    
    read -p "Enter IRAN IP    : " iran_ip
    read -p "Enter Kharej IP  : " kharej_ip
    read -p "Enter IPv6 Local : " ipv6_local
    
    cat <<EOL > /etc/netplan/mramini-$1.yaml
network:
  version: 2
  tunnels:
    tunnel0858-$1:
      mode: sit
      local: $kharej_ip
      remote: $iran_ip
      addresses:
        - $ipv6_local::2/64
EOL
    netplan_setup
    sudo netplan apply

    start_obfs4

    cat <<EOL > /root/connectors-$1.sh
ping $ipv6_local::1
EOL

    chmod +x /root/connectors-$1.sh

    screen -dmS connectors_session_$1 bash -c "/root/connectors-$1.sh"

    echo "Kharej Server $1 setup complete."
    echo -e "####################################"
    echo -e "# Your IPv6 :                      #"
    echo -e "#  $ipv6_local::2                  #"
    echo -e "####################################"
}

check_core_status() {
    local file_path="/etc/netplan/mramini-1.yaml"
    local status

    if [ -f "$file_path" ]; then
        status="${GREEN}Installed${NC}"
    else
        status="${RED}Not installed${NC}"
    fi

    echo "$status"
}

netplan_setup() {
    command -v netplan &> /dev/null || { 
        sudo apt update && sudo apt install -y netplan.io && echo "netplan installed successfully." || echo "Failed to install netplan."; 
    }
}

unistall() {
    echo $'\e[32mUninstalling Nebula in 3 seconds... \e[0m' && sleep 1 && echo $'\e[32m2... \e[0m' && sleep 1 && echo $'\e[32m1... \e[0m' && sleep 1 && {
    rm /etc/netplan/mramini*.yaml
    rm /root/connectors-*.sh
    pkill screen
    clear
    echo 'Nebula Uninstalled :(';
    systemctl stop ping-monitor.service
    systemctl disable ping-monitor.service
    rm /etc/systemd/system/ping-monitor.service
    rm /root/ping_monitor.sh
    }
    loader
}

loader() {
    nebula_menu "| 1  - Config Tunnel \n| 2  - Unistall\n| 3  - Install BBR\n| 0  - Exit"

    read -p "Enter option number: " choice
    case $choice in
    1)
        install_tunnel
        ;;  
    2)
        unistall
        ;;
    3)
    	echo "Running BBR script..."
        curl -fsSL https://raw.githubusercontent.com/MrAminiDev/NetOptix/main/scripts/bbr.sh -o /tmp/bbr.sh
	bash /tmp/bbr.sh
	rm /tmp/bbr.sh
	;;
    0)
        echo -e "${GREEN}Exiting program...${NC}"
        exit 0
        ;;
    *)
        echo "Not valid"
        ;;
    esac
}

init
loader
