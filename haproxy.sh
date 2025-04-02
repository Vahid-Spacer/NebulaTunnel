#!/bin/bash

CONFIG_FILE="/etc/haproxy/haproxy.cfg"
BACKUP_FILE="/etc/haproxy/haproxy.cfg.bak"

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root"
        exit 1
    fi
}

install_haproxy() {
    echo "Installing HAProxy..."
    apt-get update && apt-get install -y haproxy
    echo "HAProxy installed."
    set_default_config
}

set_default_config() {
    cat <<EOL > "$CONFIG_FILE"
global
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    mode    tcp
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000
EOL
}

generate_haproxy_config() {
    local -a ports target_ips
    IFS=',' read -ra ports <<< "$1"
    IFS=',' read -ra target_ips <<< "$2"

    echo "Generating HAProxy configuration..."
    for port in "${ports[@]}"; do
        cat <<EOL >> "$CONFIG_FILE"

frontend frontend_$port
    bind *:$port
    default_backend backend_$port

backend backend_$port
EOL
        for i in "${!target_ips[@]}"; do
            local mode=""
            [ $i -ne 0 ] && mode=" backup"
            echo "    server server$((i+1)) ${target_ips[$i]}:$port check$mode" >> "$CONFIG_FILE"
        done
    done
    echo "HAProxy configuration updated."
}

add_ip_ports() {
    read -p "Enter target IP: " user_ips
    read -p "Enter ports (comma-separated): " user_ports
    generate_haproxy_config "$user_ports" "$user_ips"
    
    if haproxy -c -f "$CONFIG_FILE"; then
        echo "Restarting HAProxy..."
        systemctl restart haproxy
        echo "HAProxy restarted successfully."
    else
        echo "Invalid HAProxy configuration!"
    fi
}

clear_configs() {
    echo "Backing up current configuration..."
    cp "$CONFIG_FILE" "$BACKUP_FILE" || { echo "Backup failed!"; return; }

    echo "Clearing existing IP and port configurations..."
    awk '!/^frontend frontend_/ && !/^backend backend_/' "$BACKUP_FILE" > "$CONFIG_FILE"
    
    echo "Stopping HAProxy..."
    systemctl stop haproxy && echo "HAProxy stopped." || echo "Failed to stop HAProxy."
    echo "Configuration cleared."
}

remove_haproxy() {
    echo "Removing HAProxy..."
    apt-get remove --purge -y haproxy && apt-get autoremove -y
    echo "HAProxy removed."
}

check_root

while true; do
    clear
    cat <<MENU
+------------------------------------------------------------+
| HAProxy Management Menu (Dev.MrAmini)                      |
+------------------------------------------------------------+
| 1) Install HAProxy                                         |
| 2) Add IPs and Ports                                       |
| 3) Clear Configurations                                    |
| 4) Remove HAProxy                                          |
| 9) Exit                                                    |
+------------------------------------------------------------+
MENU
    read -p "Select an option: " choice
    case $choice in
        1) install_haproxy ;;
        2) add_ip_ports ;;
        3) clear_configs ;;
        4) remove_haproxy ;;
        9) echo "Exiting..."; break ;;
        *) echo "Invalid option. Try again." ;;
    esac
    sleep 1.5
done
