#!/bin/bash

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'
UNDERLINE='\033[4m'

# --- Icons ---
ICON_GEAR="⚙️"
ICON_DOWNLOAD="📥"
ICON_SERVER="🖥️"
ICON_KEY="🔑"
ICON_SHIELD="🛡️"
ICON_SUCCESS="✅"
ICON_ERROR="❌"
ICON_EXIT="👋"
ICON_INFO="ℹ️"
ICON_QUESTION="❓"

# --- Variables & Constants ---
APP_NAME="Aura"
VERSION="v1.0.0"
BASE_INSTALL_DIR="/root/phoenix"
INSTALL_DIR="/root/phoenix"
SERVICE_FILE="/etc/systemd/system/phoenix.service"
GITHUB_LINK="https://github.com/Fox-Fig/phoenix"
TELEGRAM_LINK="https://t.me/AltBypassLab"

# --- UI Helpers ---
print_line() {
    echo -e "${CYAN}──────────────────────────────────────────────────────────────${NC}"
}

print_double_line() {
    echo -e "${MAGENTA}==============================================================${NC}"
}

print_banner() {
    clear
    echo -e "${CYAN}┌────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${MAGENTA}${BOLD}"
    echo "     █████╗ ██╗   ██╗██████╗  █████╗ "
    echo "    ██╔══██╗██║   ██║██╔══██╗██╔══██╗"
    echo "    ███████║██║   ██║██████╔╝███████║"
    echo "    ██╔══██║██║   ██║██╔══██╗██╔══██║"
    echo "    ██║  ██║╚██████╔╝██║  ██║██║  ██║"
    echo "    ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝"
    echo -e "${NC}"
    echo -e "         ${BOLD}Phoenix Tunnel Manager - ${YELLOW}${VERSION}${NC}"
    # echo -e "         ${BLUE}Channel: ${TELEGRAM_LINK}${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
    
    # Status Section - Show all instances
    local server_instances=($(detect_instances "server"))
    local client_instances=($(detect_instances "client"))
    
    if [ ${#server_instances[@]} -gt 0 ]; then
        echo -e "\n${BOLD}${MAGENTA}Servers:${NC}"
        for inst in "${server_instances[@]}"; do
            if systemctl is-active --quiet "$inst"; then
                echo -e " ${ICON_SUCCESS} ${GREEN}${BOLD}$inst: ACTIVE${NC}"
            else
                echo -e " ${ICON_GEAR} ${YELLOW}${BOLD}$inst: INACTIVE${NC}"
            fi
        done
    fi
    
    if [ ${#client_instances[@]} -gt 0 ]; then
        echo -e "\n${BOLD}${MAGENTA}Clients:${NC}"
        for inst in "${client_instances[@]}"; do
            if systemctl is-active --quiet "$inst"; then
                echo -e " ${ICON_SUCCESS} ${GREEN}${BOLD}$inst: ACTIVE${NC}"
            else
                echo -e " ${ICON_GEAR} ${YELLOW}${BOLD}$inst: INACTIVE${NC}"
            fi
        done
    fi
    
    if [ ${#server_instances[@]} -eq 0 ] && [ ${#client_instances[@]} -eq 0 ]; then
        echo -e " ${ICON_ERROR} ${RED}${BOLD}Status: NOT INSTALLED${NC}"
    fi
    
    echo ""
}

ask_question() {
    local msg="$1"
    local default="$2"
    print_line
    if [ -n "$default" ]; then
        echo -ne "${ICON_QUESTION} ${YELLOW}${BOLD}${msg}${NC} [Default: ${CYAN}${default}${NC}]: ${GREEN}"
    else
        echo -ne "${ICON_QUESTION} ${YELLOW}${BOLD}${msg}${NC}: ${GREEN}"
    fi
}

print_box() {
    local title="$1"
    local content="$2"
    echo -e "\n${CYAN}┌── $title ──────────────────────────────────────────┐${NC}"
    echo -e "  ${BOLD}${GREEN}>> ${YELLOW}$content${NC}"
    echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}\n"
}

wait_for_enter() {
    echo -e "\n${YELLOW}Press [Enter] to continue...${NC}"
    read -r
}

# --- Core Functions ---

check_root() {
    if [[ $EUID -ne 0 ]]; then
       echo -e "${RED}${ICON_ERROR} Error: This script must be run as root!${NC}"
       exit 1
    fi
}

detect_architecture() {
    local arch=$(uname -m)
    case $arch in
        x86_64|amd64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

install_dependencies() {
    if ! command -v wget &> /dev/null || ! command -v unzip &> /dev/null || ! command -v ss &> /dev/null; then
        echo -e "${BLUE}${ICON_GEAR} Installing basic dependencies...${NC}"
        apt update && apt install -y wget unzip iproute2 curl > /dev/null 2>&1
    fi
    
    # Ensure curl is installed for connection testing
    if ! command -v curl &> /dev/null; then
        apt install -y curl > /dev/null 2>&1
    fi
}

is_port_in_use() {
    local port=$1
    if ss -tuln | grep -q ":$port "; then
        return 0 
    else
        return 1
    fi
}

detect_instances() {
    local type="$1"  # "server" or "client"
    local instances=()
    
    if [ "$type" == "server" ]; then
        # Find all phoenix server services
        for service in /etc/systemd/system/phoenix*.service; do
            if [ -f "$service" ] && ! [[ "$service" =~ client ]]; then
                local name=$(basename "$service" .service)
                instances+=("$name")
            fi
        done
    else
        # Find all phoenix client services
        for service in /etc/systemd/system/phoenix*client*.service; do
            if [ -f "$service" ]; then
                local name=$(basename "$service" .service)
                instances+=("$name")
            fi
        done
    fi
    
    echo "${instances[@]}"
}

get_service_name() {
    basename "$SERVICE_FILE" .service
}

select_instance() {
    local type="$1"  # "server" or "client"
    local action="$2"  # "manage" or "install"
    
    local instances=($(detect_instances "$type"))
    
    if [ "$action" == "manage" ] && [ ${#instances[@]} -eq 0 ]; then
        return 1
    fi
    
    if [ ${#instances[@]} -eq 0 ] || [ "$action" == "install" ]; then
        # No instances or installing new one
        print_banner
        echo -e "${CYAN}${BOLD}${ICON_INFO} Instance Name${NC}\n"
        
        if [ ${#instances[@]} -gt 0 ]; then
            echo -e "${YELLOW}Existing instances:${NC}"
            for inst in "${instances[@]}"; do
                local status="⚫"
                if systemctl is-active --quiet "$inst"; then
                    status="${GREEN}●${NC}"
                fi
                echo -e "  $status $inst"
            done
            echo ""
        fi
        
        local instance_name=""
        local valid_name=false
        
        while [ "$valid_name" = false ]; do
            if [ "$type" == "server" ]; then
                ask_question "Enter server name (English only, e.g., de, us, uk)" "main"
            else
                ask_question "Enter client name (English only, e.g., iran1, tehran, home)" "main"
            fi
            read -r user_input
            user_input=${user_input:-main}
            echo -en "${NC}"
            
            # Check if input contains only English letters, numbers, hyphens, and underscores
            if [[ "$user_input" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                valid_name=true
                # Convert to lowercase
                user_input=$(echo "$user_input" | tr '[:upper:]' '[:lower:]')
                
                # Build instance name
                if [ "$type" == "server" ]; then
                    instance_name="phoenix-${user_input}"
                else
                    instance_name="phoenix-${user_input}-client"
                fi
            else
                echo -e "\n${RED}${ICON_ERROR} Invalid name! Only English letters, numbers, hyphens, and underscores are allowed.${NC}"
                echo -e "${YELLOW}Please use only: a-z, A-Z, 0-9, - (hyphen), and _ (underscore)${NC}"
                echo -e "${YELLOW}Examples: de, us, iran1, server_1, home${NC}\n"
                sleep 2
            fi
        done
        
        INSTALL_DIR="${BASE_INSTALL_DIR}/${instance_name}"
        SERVICE_FILE="/etc/systemd/system/${instance_name}.service"
        
        echo -e "\n${GREEN}${ICON_SUCCESS} Instance: ${CYAN}${instance_name}${NC}"
        echo -e "${GREEN}${ICON_SUCCESS} Directory: ${CYAN}${INSTALL_DIR}${NC}\n"
        sleep 1
        
        return 0
    else
        # Multiple instances exist, let user choose
        print_banner
        echo -e "${CYAN}${BOLD}${ICON_INFO} Select Instance${NC}\n"
        
        local i=1
        for inst in "${instances[@]}"; do
            local status="⚫ INACTIVE"
            local color="${RED}"
            if systemctl is-active --quiet "$inst"; then
                status="● ACTIVE"
                color="${GREEN}"
            fi
            echo -e "  $i) ${color}${inst}${NC} - $status"
            ((i++))
        done
        echo -e "  0) ${YELLOW}Back${NC}\n"
        
        ask_question "Select instance" "1"
        read -r choice
        choice=${choice:-1}
        echo -en "${NC}"
        
        if [ "$choice" == "0" ]; then
            return 1
        fi
        
        if [ "$choice" -ge 1 ] && [ "$choice" -le ${#instances[@]} ]; then
            local selected="${instances[$((choice-1))]}"
            INSTALL_DIR="${BASE_INSTALL_DIR}/${selected}"
            SERVICE_FILE="/etc/systemd/system/${selected}.service"
            
            echo -e "${GREEN}${ICON_SUCCESS} Selected: ${CYAN}${selected}${NC}\n"
            sleep 1
            return 0
        else
            echo -e "${RED}Invalid choice!${NC}"
            sleep 1
            return 1
        fi
    fi
}

test_proxy_connection() {
    local socks_port="$1"
    
    print_banner
    echo -e "${CYAN}${BOLD}${ICON_GEAR} Testing Proxy Connection...${NC}\n"
    
    # Check if port is listening
    if ! ss -tuln | grep -q ":$socks_port "; then
        echo -e "${RED}${ICON_ERROR} Socks5 proxy is not running on port $socks_port!${NC}"
        echo -e "${YELLOW}Please make sure phoenix-client service is active.${NC}"
        wait_for_enter
        return
    fi
    
    echo -e "${GREEN}${ICON_SUCCESS} Socks5 proxy is listening on port $socks_port${NC}\n"
    
    print_line
    echo -e "${BLUE}${BOLD}Testing connection through proxy...${NC}\n"
    
    # Test 1: Get IP and location info
    echo -e "${CYAN}📍 Fetching IP information...${NC}"
    local ip_info=$(curl -s --socks5 127.0.0.1:$socks_port --max-time 10 "https://api.myip.com" 2>/dev/null)
    
    if [ -n "$ip_info" ]; then
        # Parse JSON response from api.myip.com
        local ip=$(echo "$ip_info" | grep -o '"ip":"[^"]*"' | cut -d'"' -f4)
        local country=$(echo "$ip_info" | grep -o '"country":"[^"]*"' | cut -d'"' -f4)
        local cc=$(echo "$ip_info" | grep -o '"cc":"[^"]*"' | cut -d'"' -f4)
        
        echo -e "${GREEN}${ICON_SUCCESS} Connection successful!${NC}\n"
        
        # Display connection details in box
        echo -e "${CYAN}┌── Connection Details ──────────────────────────────────────┐${NC}"
        echo -e "  ${BOLD}${WHITE}IP Address:${NC}  ${CYAN}${ip:-N/A}${NC}"
        echo -e "  ${BOLD}${WHITE}Country:${NC}     ${CYAN}${country:-N/A}${NC}"
        if [ -n "$cc" ]; then
            echo -e "  ${BOLD}${WHITE}Code:${NC}        ${CYAN}${cc}${NC}"
        fi
        echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
    else
        echo -e "${RED}${ICON_ERROR} Failed to connect through proxy!${NC}"
        echo -e "${YELLOW}Possible issues:${NC}"
        echo -e "  - Server is not reachable"
        echo -e "  - Wrong server configuration"
        echo -e "  - Firewall blocking connection"
        wait_for_enter
        return
    fi
    
    # Test 2: Measure latency
    echo -e "\n${CYAN}⏱️  Measuring latency...${NC}"
    local total_time=0
    local success_count=0
    
    for i in {1..3}; do
        local start_time=$(date +%s%3N)
        local response=$(curl -s --socks5 127.0.0.1:$socks_port --max-time 5 -o /dev/null -w "%{http_code}" "https://www.google.com" 2>/dev/null)
        local end_time=$(date +%s%3N)
        
        if [ "$response" == "200" ] || [ "$response" == "301" ] || [ "$response" == "302" ]; then
            local ping_time=$((end_time - start_time))
            total_time=$((total_time + ping_time))
            success_count=$((success_count + 1))
            echo -e "  ${GREEN}✓${NC} Test $i: ${CYAN}${ping_time}ms${NC}"
        else
            echo -e "  ${RED}✗${NC} Test $i: Failed"
        fi
    done
    
    if [ $success_count -gt 0 ]; then
        local avg_ping=$((total_time / success_count))
        echo -e "\n${BOLD}${WHITE}Average Latency:${NC} ${CYAN}${avg_ping}ms${NC}"
        
        if [ $avg_ping -lt 100 ]; then
            echo -e "${GREEN}${ICON_SUCCESS} Excellent connection!${NC}"
        elif [ $avg_ping -lt 300 ]; then
            echo -e "${YELLOW}⚠️  Good connection${NC}"
        else
            echo -e "${YELLOW}⚠️  High latency detected${NC}"
        fi
    fi
    
    print_double_line
    echo -e "${GREEN}${BOLD}${ICON_SUCCESS} Proxy Test Completed!${NC}"
    print_double_line
    
    wait_for_enter
}

setup_server() {
    # Select or create instance
    if ! select_instance "server" "install"; then
        return
    fi
    
    print_banner
    
    # Auto-detect architecture
    local detected_arch=$(detect_architecture)
    echo -e "${BLUE}${ICON_INFO} Detected Architecture: ${CYAN}${BOLD}$detected_arch${NC}"
    
    if [ "$detected_arch" == "unknown" ]; then
        echo -e "${RED}${ICON_ERROR} Unsupported architecture!${NC}"
        wait_for_enter
        return
    fi
    
    # Set download URL based on detected architecture
    if [ "$detected_arch" == "arm64" ]; then
        PLATFORM="linux-arm64"
        URL="https://github.com/Fox-Fig/phoenix/releases/latest/download/phoenix-server-linux-arm64.zip"
        echo -e "${GREEN}${ICON_SUCCESS} Using ARM64 binary${NC}\n"
    else
        PLATFORM="linux-amd64"
        URL="https://github.com/Fox-Fig/phoenix/releases/latest/download/phoenix-server-linux-amd64.zip"
        echo -e "${GREEN}${ICON_SUCCESS} Using AMD64 binary${NC}\n"
    fi

    while true; do
        ask_question "Enter Listen Port" "443"
        read -r port_num
        port_num=${port_num:-443}
        echo -en "${NC}"
        if is_port_in_use "$port_num"; then
            echo -e "${RED}${ICON_ERROR} Port $port_num is occupied!${NC}"
        else
            break
        fi
    done

    mkdir -p "$INSTALL_DIR"
    echo -e "${BLUE}${ICON_DOWNLOAD} Downloading & Extracting binaries for $PLATFORM...${NC}"
    wget -q "$URL" -O "$INSTALL_DIR/phoenix.zip"
    unzip -oq "$INSTALL_DIR/phoenix.zip" -d "$INSTALL_DIR"
    rm -f "$INSTALL_DIR/phoenix.zip"
    
    echo -e "${GREEN}${BOLD}${ICON_SUCCESS} Binaries installed successfully!${NC}"
    
    cd "$INSTALL_DIR" || return
    chmod +x phoenix-server

    # Protocol Configuration
    print_line
    echo -e "${BOLD}${MAGENTA}>> STEP 2: Protocol Configuration${NC}"
    echo -e "${CYAN}┌────────────────────────────────────────────────────────────┐${NC}"
    echo -e "  Select which protocols clients can use:"
    echo -e "  ${GREEN}SOCKS5${NC} - Universal proxy (Recommended)"
    echo -e "  ${BLUE}UDP${NC} - Required for modern services (YouTube, Instagram)"
    echo -e "  ${YELLOW}SSH${NC} - SSH tunnel support"
    echo -e "  ${MAGENTA}Shadowsocks${NC} - Shadowsocks protocol"
    echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
    
    # SOCKS5
    ask_question "Enable SOCKS5? (y/n)" "y"
    read -r enable_socks5
    enable_socks5=${enable_socks5:-y}
    echo -en "${NC}"
    
    # UDP
    ask_question "Enable UDP? (y/n)" "y"
    read -r enable_udp
    enable_udp=${enable_udp:-y}
    echo -en "${NC}"
    
    # SSH
    ask_question "Enable SSH Tunnel? (y/n)" "n"
    read -r enable_ssh
    enable_ssh=${enable_ssh:-n}
    echo -en "${NC}"
    
    # Shadowsocks
    ask_question "Enable Shadowsocks? (y/n)" "n"
    read -r enable_shadowsocks
    enable_shadowsocks=${enable_shadowsocks:-n}
    echo -en "${NC}"
    
    # Convert to boolean
    local socks5_bool="false"
    local udp_bool="false"
    local ssh_bool="false"
    local ss_bool="false"
    
    [[ "$enable_socks5" == "y" ]] && socks5_bool="true"
    [[ "$enable_udp" == "y" ]] && udp_bool="true"
    [[ "$enable_ssh" == "y" ]] && ssh_bool="true"
    [[ "$enable_shadowsocks" == "y" ]] && ss_bool="true"

    # Setup Security
    print_line
    echo -e "${BOLD}${MAGENTA}>> STEP 3: Security Configuration${NC}"
    echo -e "${CYAN}┌────────────────────────────────────────────────────────────┐${NC}"
    echo -e "  1) ${WHITE}${BOLD}NO TLS${NC} (Plain h2c - Not Recommended)"
    echo -e "  2) ${WHITE}${BOLD}One-Way TLS${NC} (HTTPS Style - Standard Security)"
    echo -e "  3) ${GREEN}${BOLD}mTLS (Mutual TLS)${NC} ${YELLOW}[Recommended - Highest Security]${NC}"
    echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
    
    ask_question "Selection" "3"
    read -r sec_mode
    sec_mode=${sec_mode:-3}
    echo -en "${NC}"

    # Base Config
    cat <<EOF > server.toml
listen_addr = "0.0.0.0:$port_num"

[security]
enable_socks5 = $socks5_bool
enable_udp = $udp_bool
enable_shadowsocks = $ss_bool
enable_ssh = $ssh_bool
EOF

    case $sec_mode in
        2|3)
            echo -e "\n${BLUE}${ICON_KEY} ${BOLD}STEP 4: Generating Server Keys${NC}"
            cd "$INSTALL_DIR" || return
            
            # Generate server keys
            ./phoenix-server -gen-keys > key_output.tmp 2>&1
            sleep 1
            
            # Extract server public key from different possible formats
            server_pub_key=$(grep -i "public key" key_output.tmp | grep -oE '[A-Za-z0-9+/=]{40,}' | head -n1)
            
            # Check if server_private.key or private.key file was created
            if [ -f "server_private.key" ]; then
                mv -f server_private.key server.private.key
                echo -e "${GREEN}${ICON_SUCCESS} Server private key saved as: server.private.key${NC}"
            elif [ -f "private.key" ]; then
                mv -f private.key server.private.key
                echo -e "${GREEN}${ICON_SUCCESS} Server private key saved as: server.private.key${NC}"
            else
                echo -e "${RED}${ICON_ERROR} Failed to generate server private key!${NC}"
                echo -e "${YELLOW}Raw output:${NC}"
                cat key_output.tmp
                wait_for_enter
                rm -f key_output.tmp
                return
            fi
            
            # If extraction failed, show output and ask for manual input
            if [ -z "$server_pub_key" ]; then
                echo -e "\n${YELLOW}${ICON_INFO} Raw output from key generation:${NC}"
                print_line
                cat key_output.tmp
                print_line
                
                ask_question "Please paste SERVER PUBLIC KEY from above"
                read -r server_pub_key
                echo -en "${NC}"
            fi
            
            rm -f key_output.tmp

            # Add private key to server config
            sed -i '/\[security\]/a private_key = "server.private.key"' "$INSTALL_DIR/server.toml"
            
            # Save server public key to file for easy access
            echo "$server_pub_key" > "$INSTALL_DIR/server_public.key"
            
            echo -e "\n${GREEN}${BOLD}${ICON_SUCCESS} Server Key Generated Successfully!${NC}"
            print_box "SERVER PUBLIC KEY (Copy to client.toml)" "$server_pub_key"
            
            echo -e "${YELLOW}${BOLD}STEP 5: Configure Client${NC}"
            echo -e "${CYAN}Add this to your client.toml:${NC}"
            echo -e "${WHITE}server_public_key = \"$server_pub_key\"${NC}\n"
            
            if [[ "$sec_mode" == "3" ]]; then
                print_double_line
                echo -e "${MAGENTA}${BOLD}${ICON_SHIELD} mTLS Configuration (Mutual Authentication)${NC}"
                print_double_line
                
                echo -e "${YELLOW}${BOLD}STEP 6: Generate Client Keys${NC}"
                echo -e "${CYAN}On your CLIENT machine, run these commands:${NC}"
                echo -e "${WHITE}  ./phoenix-client -gen-keys${NC}"
                echo -e "${WHITE}  mv client_private.key client.private.key${NC}\n"
                
                echo -e "${YELLOW}${BOLD}STEP 7: Configure client.toml${NC}"
                echo -e "${CYAN}Add this line to your client.toml:${NC}"
                echo -e "${WHITE}  private_key = \"client.private.key\"${NC}\n"
                
                echo -e "${YELLOW}${BOLD}STEP 8: Authorize Client on Server${NC}"
                echo -e "${CYAN}After running step 3, copy the CLIENT PUBLIC KEY and paste it below:${NC}\n"
                
                ask_question "Paste CLIENT PUBLIC KEY here (or press Enter to skip)"
                read -r client_pub_key
                echo -en "${NC}"
                
                if [ -n "$client_pub_key" ]; then
                    # Add authorized_clients to server config
                    cat >> "$INSTALL_DIR/server.toml" <<EOF

# mTLS: Only authorized clients can connect
authorized_clients = [
  "$client_pub_key"
]
EOF
                    echo -e "\n${GREEN}${ICON_SUCCESS} mTLS configured! Only your client can connect.${NC}"
                    print_double_line
                    echo -e "${GREEN}${BOLD}${ICON_SUCCESS} mTLS Setup Complete!${NC}"
                    echo -e "${CYAN}Your tunnel now has maximum security (Anti-Probing).${NC}"
                    print_double_line
                else
                    echo -e "\n${YELLOW}${ICON_INFO} Skipped client key. You can add it later by:${NC}"
                    echo -e "${CYAN}1. Run './phoenix-client -gen-keys' on client${NC}"
                    echo -e "${CYAN}2. Copy the public key${NC}"
                    echo -e "${CYAN}3. Add to server.toml: authorized_clients = [\"KEY_HERE\"]${NC}\n"
                fi
            fi
            ;;
    esac

    chmod 600 "$INSTALL_DIR"/*.key 2>/dev/null

    # Service Creation
    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Phoenix Tunnel Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/phoenix-server -config $INSTALL_DIR/server.toml
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    local service_name=$(get_service_name)
    systemctl enable "$service_name" --now > /dev/null 2>&1
    
    print_double_line
    echo -e "${GREEN}${BOLD}${ICON_SUCCESS} Installation Completed Successfully!${NC}"
    print_double_line
    wait_for_enter
}

setup_client() {
    # Select or create instance
    if ! select_instance "client" "install"; then
        return
    fi
    
    print_banner
    
    # Auto-detect architecture
    local detected_arch=$(detect_architecture)
    echo -e "${BLUE}${ICON_INFO} Detected Architecture: ${CYAN}${BOLD}$detected_arch${NC}"
    
    if [ "$detected_arch" == "unknown" ]; then
        echo -e "${RED}${ICON_ERROR} Unsupported architecture!${NC}"
        wait_for_enter
        return
    fi
    
    # Set download URL based on detected architecture
    if [ "$detected_arch" == "arm64" ]; then
        PLATFORM="linux-arm64"
        URL="https://github.com/Fox-Fig/phoenix/releases/latest/download/phoenix-client-linux-arm64.zip"
        echo -e "${GREEN}${ICON_SUCCESS} Using ARM64 binary${NC}\n"
    else
        PLATFORM="linux-amd64"
        URL="https://github.com/Fox-Fig/phoenix/releases/latest/download/phoenix-client-linux-amd64.zip"
        echo -e "${GREEN}${ICON_SUCCESS} Using AMD64 binary${NC}\n"
    fi
    
    # Ask for Socks5 port
    print_line
    echo -e "${BOLD}${MAGENTA}>> STEP 1: Inbound Configuration${NC}"
    echo -e "${CYAN}┌────────────────────────────────────────────────────────────┐${NC}"
    echo -e "  Select protocols to enable (you can enable multiple):"
    echo -e "  1) ${GREEN}SOCKS5${NC} - Universal proxy (Recommended)"
    echo -e "  2) ${BLUE}SSH${NC} - SSH tunnel"
    echo -e "  3) ${YELLOW}Shadowsocks${NC} - Shadowsocks proxy"
    echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
    
    # SOCKS5
    ask_question "Enable SOCKS5? (y/n)" "y"
    read -r enable_socks5
    enable_socks5=${enable_socks5:-y}
    echo -en "${NC}"
    
    local socks_port=""
    if [[ "$enable_socks5" == "y" ]]; then
        while true; do
            ask_question "Enter SOCKS5 Listen Port" "1080"
            read -r socks_port
            socks_port=${socks_port:-1080}
            echo -en "${NC}"
            if is_port_in_use "$socks_port"; then
                echo -e "${RED}${ICON_ERROR} Port $socks_port is occupied!${NC}"
            else
                break
            fi
        done
    fi
    
    # SSH
    ask_question "Enable SSH Tunnel? (y/n)" "n"
    read -r enable_ssh
    enable_ssh=${enable_ssh:-n}
    echo -en "${NC}"
    
    local ssh_port=""
    if [[ "$enable_ssh" == "y" ]]; then
        while true; do
            ask_question "Enter SSH Listen Port" "2022"
            read -r ssh_port
            ssh_port=${ssh_port:-2022}
            echo -en "${NC}"
            if is_port_in_use "$ssh_port"; then
                echo -e "${RED}${ICON_ERROR} Port $ssh_port is occupied!${NC}"
            else
                break
            fi
        done
    fi
    
    # Shadowsocks
    ask_question "Enable Shadowsocks? (y/n)" "n"
    read -r enable_ss
    enable_ss=${enable_ss:-n}
    echo -en "${NC}"
    
    local ss_port=""
    local ss_password=""
    local ss_method=""
    if [[ "$enable_ss" == "y" ]]; then
        while true; do
            ask_question "Enter Shadowsocks Listen Port" "8388"
            read -r ss_port
            ss_port=${ss_port:-8388}
            echo -en "${NC}"
            if is_port_in_use "$ss_port"; then
                echo -e "${RED}${ICON_ERROR} Port $ss_port is occupied!${NC}"
            else
                break
            fi
        done
        
        ask_question "Enter Shadowsocks Password"
        read -r ss_password
        echo -en "${NC}"
        
        ask_question "Enter Encryption Method" "chacha20-ietf-poly1305"
        read -r ss_method
        ss_method=${ss_method:-chacha20-ietf-poly1305}
        echo -en "${NC}"
    fi
    
    # Download and extract
    mkdir -p "$INSTALL_DIR"
    echo -e "${BLUE}${ICON_DOWNLOAD} Downloading & Extracting client binaries for $PLATFORM...${NC}"
    wget -q "$URL" -O "$INSTALL_DIR/phoenix.zip"
    unzip -oq "$INSTALL_DIR/phoenix.zip" -d "$INSTALL_DIR"
    rm -f "$INSTALL_DIR/phoenix.zip"
    
    echo -e "${GREEN}${BOLD}${ICON_SUCCESS} Binaries installed successfully!${NC}"
    
    cd "$INSTALL_DIR" || return
    chmod +x phoenix-client
    
    # Security Configuration
    print_line
    echo -e "${BOLD}${MAGENTA}>> STEP 2: Security Configuration${NC}"
    echo -e "${CYAN}┌────────────────────────────────────────────────────────────┐${NC}"
    echo -e "  1) ${WHITE}${BOLD}NO TLS${NC} (Plain h2c - Not Recommended)"
    echo -e "  2) ${WHITE}${BOLD}One-Way TLS${NC} (HTTPS Style - Standard Security)"
    echo -e "  3) ${GREEN}${BOLD}mTLS (Mutual TLS)${NC} ${YELLOW}[Recommended - Highest Security]${NC}"
    echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
    
    ask_question "Selection" "3"
    read -r sec_mode
    sec_mode=${sec_mode:-3}
    echo -en "${NC}"
    
    # Ask for server details
    print_line
    echo -e "${BOLD}${MAGENTA}>> STEP 3: Server Connection Details${NC}"
    
    ask_question "Enter Server IP/Domain"
    read -r server_addr
    echo -en "${NC}"
    
    ask_question "Enter Server Port" "443"
    read -r server_port
    server_port=${server_port:-443}
    echo -en "${NC}"
    
    # Base client config
    cat <<EOF > client.toml
# Phoenix Client Configuration
# Generated by Aura Script

# Server address and port
remote_addr = "$server_addr:$server_port"

EOF
    
    case $sec_mode in
        2|3)
            print_line
            echo -e "${BLUE}${ICON_KEY} ${BOLD}Configuring TLS Security${NC}\n"
            
            ask_question "Enter SERVER PUBLIC KEY (from server)"
            read -r server_pub_key
            echo -en "${NC}"
            
            # Add server public key to config
            cat >> "$INSTALL_DIR/client.toml" <<EOF
# Server's public key for secure connection
server_public_key = "$server_pub_key"

EOF
            
            if [[ "$sec_mode" == "3" ]]; then
                print_double_line
                echo -e "${MAGENTA}${BOLD}${ICON_SHIELD} mTLS Configuration (Mutual Authentication)${NC}"
                print_double_line
                
                echo -e "${YELLOW}${BOLD}Generating Client Keys...${NC}"
                cd "$INSTALL_DIR" || return
                
                # Generate client keys
                ./phoenix-client -gen-keys > key_output.tmp 2>&1
                sleep 1
                
                # Extract client public key from different possible formats
                client_pub_key=$(grep -i "public key" key_output.tmp | grep -oE '[A-Za-z0-9+/=]{40,}' | head -n1)
                
                # Check if private key file was created and rename it properly
                if [ -f "private.key" ]; then
                    mv -f private.key client.private.key
                    echo -e "${GREEN}${ICON_SUCCESS} Client private key renamed to: client.private.key${NC}"
                elif [ -f "client_private.key" ]; then
                    mv -f client_private.key client.private.key
                    echo -e "${GREEN}${ICON_SUCCESS} Client private key renamed to: client.private.key${NC}"
                elif [ -f "client.private.key" ]; then
                    echo -e "${GREEN}${ICON_SUCCESS} Client private key already exists: client.private.key${NC}"
                else
                    echo -e "${RED}${ICON_ERROR} Failed to generate client private key!${NC}"
                    echo -e "${YELLOW}Raw output:${NC}"
                    cat key_output.tmp
                    echo -e "\n${YELLOW}Files in directory:${NC}"
                    ls -la *.key 2>/dev/null || echo "No key files found"
                    wait_for_enter
                    rm -f key_output.tmp
                    return
                fi
                
                # If extraction failed, show output and ask for manual input
                if [ -z "$client_pub_key" ]; then
                    echo -e "\n${YELLOW}${ICON_INFO} Raw output from key generation:${NC}"
                    print_line
                    cat key_output.tmp
                    print_line
                    
                    ask_question "Please paste CLIENT PUBLIC KEY from above"
                    read -r client_pub_key
                    echo -en "${NC}"
                fi
                
                rm -f key_output.tmp
                
                # Add private key to client config
                sed -i '/server_public_key/a private_key = "client.private.key"\n' "$INSTALL_DIR/client.toml"
                
                # Save client public key to file for easy access
                echo "$client_pub_key" > "$INSTALL_DIR/client_public.key"
                
                echo -e "\n${GREEN}${BOLD}${ICON_SUCCESS} Client Key Generated Successfully!${NC}"
                print_box "CLIENT PUBLIC KEY (Add to server's authorized_clients)" "$client_pub_key"
                
                echo -e "${YELLOW}${BOLD}IMPORTANT: Add this key to your server!${NC}"
                echo -e "${CYAN}On your SERVER, add this line to server.toml:${NC}"
                echo -e "${WHITE}authorized_clients = [\"$client_pub_key\"]${NC}\n"
                
                print_double_line
                echo -e "${GREEN}${BOLD}${ICON_SUCCESS} mTLS Setup Complete!${NC}"
                echo -e "${CYAN}Your tunnel now has maximum security.${NC}"
                print_double_line
            fi
            ;;
    esac
    
    # Add inbound configuration
    if [[ "$enable_socks5" == "y" ]]; then
        cat >> "$INSTALL_DIR/client.toml" <<EOF
# Local SOCKS5 Proxy Configuration
[[inbounds]]
protocol = "socks5"
local_addr = "127.0.0.1:$socks_port"
enable_udp = true

EOF
    fi
    
    if [[ "$enable_ssh" == "y" ]]; then
        cat >> "$INSTALL_DIR/client.toml" <<EOF
# Local SSH Tunnel Configuration
[[inbounds]]
protocol = "ssh"
local_addr = "127.0.0.1:$ssh_port"

EOF
    fi
    
    if [[ "$enable_ss" == "y" ]]; then
        cat >> "$INSTALL_DIR/client.toml" <<EOF
# Local Shadowsocks Proxy Configuration
[[inbounds]]
protocol = "shadowsocks"
local_addr = "127.0.0.1:$ss_port"
auth = "$ss_method:$ss_password"

EOF
    fi
    
    chmod 600 "$INSTALL_DIR"/*.key 2>/dev/null
    
    # Create systemd service for client with correct name
    local service_name=$(get_service_name)
    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Phoenix Tunnel Client
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/phoenix-client -config $INSTALL_DIR/client.toml
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable "$service_name" --now > /dev/null 2>&1
    
    print_double_line
    echo -e "${GREEN}${BOLD}${ICON_SUCCESS} Client Installation Completed Successfully!${NC}"
    echo -e "${CYAN}Socks5 Proxy is running on: ${WHITE}127.0.0.1:$socks_port${NC}"
    print_double_line
    wait_for_enter
}

manage_client() {
    # Select instance to manage
    if ! select_instance "client" "manage"; then
        print_banner
        echo -e "${RED}${BOLD}${ICON_ERROR} Error: No Phoenix client instances found!${NC}"
        echo -e "${YELLOW}Please install a client first.${NC}"
        wait_for_enter
        return
    fi
    
    if [ ! -f "$SERVICE_FILE" ]; then
        print_banner
        echo -e "${RED}${BOLD}${ICON_ERROR} Error: Selected instance is not properly installed!${NC}"
        wait_for_enter
        return
    fi

    while true; do
        print_banner
        echo -e "${BOLD}${MAGENTA}>> Client Management Menu:${NC}"
        echo -e "   1) ${BLUE}Service Status${NC}"
        echo -e "   2) ${GREEN}Show Client Info & Keys${NC}"
        echo -e "   3) ${BLUE}Real-time Logs${NC}"
        echo -e "   4) ${BLUE}Restart Service${NC}"
        echo -e "   5) ${BLUE}Edit Config (Nano)${NC}"
        echo -e "   6) ${CYAN}Update Server Public Key${NC}"
        echo -e "   7) ${YELLOW}Regenerate Client Keys (mTLS)${NC}"
        echo -e "   8) ${MAGENTA}Generate New Client Keys Manually${NC}"
        echo -e "   9) ${GREEN}Test Proxy Connection${NC}"
        echo -e "  10) ${CYAN}Get Shadowsocks Link${NC}"
        echo -e "  11) ${CYAN}Rename Instance${NC}"
        echo -e "  12) ${RED}Uninstall Client${NC}"
        echo -e "   0) ${YELLOW}Back to Main${NC}"
        
        ask_question "Action" "0"
        read -r mgmt_act
        mgmt_act=${mgmt_act:-0}
        echo -en "${NC}"

        local service_name=$(get_service_name)
        
        case $mgmt_act in
            1) systemctl status "$service_name"; wait_for_enter ;;
            2)
                print_banner
                echo -e "${CYAN}${BOLD}${ICON_INFO} Client Information${NC}\n"
                
                # Check if config file exists
                if [ ! -f "$INSTALL_DIR/client.toml" ]; then
                    echo -e "${RED}${ICON_ERROR} Config file not found: $INSTALL_DIR/client.toml${NC}"
                    wait_for_enter
                    continue
                fi
                
                # Get server address from config
                local server_addr=$(grep "^remote_addr" "$INSTALL_DIR/client.toml" | cut -d'"' -f2)
                
                # Get local ports with improved extraction
                local socks_port=$(grep -A2 'protocol = "socks5"' "$INSTALL_DIR/client.toml" | grep "local_addr" | grep -oE ':[0-9]+' | grep -oE '[0-9]+' | head -1)
                local ssh_port=$(grep -A2 'protocol = "ssh"' "$INSTALL_DIR/client.toml" | grep "local_addr" | grep -oE ':[0-9]+' | grep -oE '[0-9]+' | head -1)
                local ss_port=$(grep -A2 'protocol = "shadowsocks"' "$INSTALL_DIR/client.toml" | grep "local_addr" | grep -oE ':[0-9]+' | grep -oE '[0-9]+' | head -1)
                
                # Display client configuration in box
                echo -e "${CYAN}┌── Client Configuration ────────────────────────────────────┐${NC}"
                echo -e "  ${BOLD}${WHITE}Server Address:${NC}  ${CYAN}$server_addr${NC}"
                
                if [ -n "$socks_port" ]; then
                    echo -e "  ${BOLD}${WHITE}SOCKS5 Port:${NC}     ${CYAN}127.0.0.1:$socks_port${NC}"
                fi
                if [ -n "$ssh_port" ]; then
                    echo -e "  ${BOLD}${WHITE}SSH Port:${NC}        ${CYAN}127.0.0.1:$ssh_port${NC}"
                fi
                if [ -n "$ss_port" ]; then
                    echo -e "  ${BOLD}${WHITE}Shadowsocks:${NC}     ${CYAN}127.0.0.1:$ss_port${NC}"
                fi
                echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
                
                # Show server public key if exists
                local server_pub=$(grep "^server_public_key" "$INSTALL_DIR/client.toml" | cut -d'"' -f2)
                if [ -n "$server_pub" ]; then
                    echo -e "\n${GREEN}${BOLD}${ICON_KEY} Server Public Key (in use):${NC}"
                    print_line
                    echo -e "${YELLOW}$server_pub${NC}"
                    print_line
                fi
                
                # Show client public key if exists
                if [ -f "$INSTALL_DIR/client_public.key" ]; then
                    local client_pub=$(cat "$INSTALL_DIR/client_public.key")
                    echo -e "\n${GREEN}${BOLD}${ICON_KEY} Client Public Key (for server):${NC}"
                    print_line
                    echo -e "${YELLOW}$client_pub${NC}"
                    print_line
                    echo -e "${CYAN}Add this key to server's authorized_clients${NC}\n"
                fi
                
                wait_for_enter
                ;;
            3) (trap 'exit' INT; journalctl -u "$service_name" -f -n 50 --no-hostname --output cat) ;;
            4) systemctl restart "$service_name"; echo -e "${GREEN}Restarted.${NC}"; sleep 1 ;;
            5) nano "$INSTALL_DIR/client.toml"; systemctl restart "$service_name" ;;
            6)
                print_banner
                echo -e "${CYAN}${BOLD}${ICON_KEY} Update Server Public Key${NC}\n"
                
                ask_question "Enter SERVER PUBLIC KEY"
                read -r new_server_key
                echo -en "${NC}"
                
                if [ -n "$new_server_key" ]; then
                    # Check if server_public_key already exists
                    if grep -q "^server_public_key" "$INSTALL_DIR/client.toml"; then
                        # Update existing key
                        sed -i "s|^server_public_key = \".*\"|server_public_key = \"$new_server_key\"|" "$INSTALL_DIR/client.toml"
                    else
                        # Add new key after remote_addr
                        sed -i "/^remote_addr/a server_public_key = \"$new_server_key\"" "$INSTALL_DIR/client.toml"
                    fi
                    
                    echo -e "\n${GREEN}${ICON_SUCCESS} Server public key updated successfully!${NC}"
                    
                    ask_question "Restart Phoenix Client service now? (y/n)" "y"
                    read -r restart_confirm
                    echo -en "${NC}"
                    
                    if [[ "$restart_confirm" == "y" ]]; then
                        systemctl restart "$service_name"
                        echo -e "${GREEN}${ICON_SUCCESS} Service restarted!${NC}"
                    fi
                fi
                wait_for_enter
                ;;
            7)
                print_banner
                echo -e "${YELLOW}${BOLD}${ICON_KEY} Regenerate Client Keys (mTLS)${NC}\n"
                echo -e "${RED}WARNING: This will generate new client keys!${NC}"
                echo -e "${YELLOW}You must update the server's authorized_clients with the new key.${NC}\n"
                
                ask_question "Continue? (y/n)" "n"
                read -r confirm_regen
                echo -en "${NC}"
                
                if [[ "$confirm_regen" == "y" ]]; then
                    cd "$INSTALL_DIR" || return
                    
                    # Backup old keys
                    [ -f "client.private.key" ] && mv client.private.key client.private.key.backup
                    [ -f "client_public.key" ] && mv client_public.key client_public.key.backup
                    
                    # Generate new keys
                    echo -e "${BLUE}${ICON_GEAR} Generating new keys...${NC}"
                    ./phoenix-client -gen-keys > key_output.tmp 2>&1
                    sleep 1
                    
                    # Extract new public key with improved method
                    local new_pub_key=$(grep -i "public key" key_output.tmp | grep -oE '[A-Za-z0-9+/=]{40,}' | head -n1)
                    
                    # Check for generated private key file and rename properly
                    if [ -f "private.key" ]; then
                        mv -f private.key client.private.key
                        echo -e "${GREEN}${ICON_SUCCESS} Private key renamed to: client.private.key${NC}"
                    elif [ -f "client_private.key" ]; then
                        mv -f client_private.key client.private.key
                        echo -e "${GREEN}${ICON_SUCCESS} Private key renamed to: client.private.key${NC}"
                    elif [ -f "client.private.key" ]; then
                        echo -e "${GREEN}${ICON_SUCCESS} Private key already exists: client.private.key${NC}"
                    else
                        echo -e "${RED}${ICON_ERROR} Failed to generate private key!${NC}"
                        echo -e "${YELLOW}Raw output:${NC}"
                        cat key_output.tmp
                        echo -e "\n${YELLOW}Files in directory:${NC}"
                        ls -la *.key 2>/dev/null || echo "No key files found"
                        rm -f key_output.tmp
                        wait_for_enter
                        return
                    fi
                    
                    # If public key extraction failed, ask for manual input
                    if [ -z "$new_pub_key" ]; then
                        echo -e "\n${YELLOW}${ICON_INFO} Could not auto-extract public key.${NC}"
                        echo -e "${YELLOW}Raw output:${NC}"
                        print_line
                        cat key_output.tmp
                        print_line
                        
                        ask_question "Please paste the PUBLIC KEY from above"
                        read -r new_pub_key
                        echo -en "${NC}"
                    fi
                    
                    rm -f key_output.tmp
                    
                    if [ -n "$new_pub_key" ]; then
                        # Save public key to file
                        echo "$new_pub_key" > client_public.key
                        
                        # Update config
                        if grep -q "^private_key" "$INSTALL_DIR/client.toml"; then
                            sed -i 's|^private_key = ".*"|private_key = "client.private.key"|' "$INSTALL_DIR/client.toml"
                        else
                            sed -i '/^server_public_key/a private_key = "client.private.key"' "$INSTALL_DIR/client.toml"
                        fi
                        
                        echo -e "\n${GREEN}${ICON_SUCCESS} New client keys generated!${NC}"
                        print_box "NEW CLIENT PUBLIC KEY" "$new_pub_key"
                        echo -e "${YELLOW}${BOLD}IMPORTANT: Update this key on your server!${NC}"
                        echo -e "${CYAN}Add to server.toml: authorized_clients = [\"$new_pub_key\"]${NC}\n"
                        
                        systemctl restart "$service_name"
                        echo -e "${GREEN}${ICON_SUCCESS} Service restarted with new keys${NC}"
                    else
                        echo -e "${RED}${ICON_ERROR} Failed to generate keys!${NC}"
                    fi
                fi
                wait_for_enter
                ;;
            8)
                print_banner
                echo -e "${MAGENTA}${BOLD}${ICON_KEY} Generate New Client Keys Manually${NC}\n"
                echo -e "${CYAN}This will generate a new key pair without modifying your config.${NC}"
                echo -e "${YELLOW}Use this if you want to create keys for a new client setup.${NC}\n"
                
                ask_question "Continue? (y/n)" "y"
                read -r confirm_gen
                echo -en "${NC}"
                
                if [[ "$confirm_gen" == "y" ]]; then
                    cd "$INSTALL_DIR" || return
                    
                    # Generate keys with timestamp to avoid conflicts
                    local timestamp=$(date +%s)
                    echo -e "${BLUE}${ICON_GEAR} Generating new keys...${NC}"
                    ./phoenix-client -gen-keys > "key_output_${timestamp}.tmp" 2>&1
                    sleep 1
                    
                    # Extract public key
                    local new_pub_key=$(grep -i "public key" "key_output_${timestamp}.tmp" | grep -oE '[A-Za-z0-9+/=]{40,}' | head -n1)
                    
                    # Check for generated private key file and rename with timestamp
                    if [ -f "private.key" ]; then
                        mv -f private.key "client_manual_${timestamp}.private.key"
                        echo -e "${GREEN}${ICON_SUCCESS} Private key saved as: client_manual_${timestamp}.private.key${NC}"
                    elif [ -f "client_private.key" ]; then
                        mv -f client_private.key "client_manual_${timestamp}.private.key"
                        echo -e "${GREEN}${ICON_SUCCESS} Private key saved as: client_manual_${timestamp}.private.key${NC}"
                    else
                        echo -e "${RED}${ICON_ERROR} Failed to generate private key!${NC}"
                        echo -e "${YELLOW}Raw output:${NC}"
                        cat "key_output_${timestamp}.tmp"
                        rm -f "key_output_${timestamp}.tmp"
                        wait_for_enter
                        continue
                    fi
                    
                    # If public key extraction failed, ask for manual input
                    if [ -z "$new_pub_key" ]; then
                        echo -e "\n${YELLOW}${ICON_INFO} Could not auto-extract public key.${NC}"
                        echo -e "${YELLOW}Raw output:${NC}"
                        print_line
                        cat "key_output_${timestamp}.tmp"
                        print_line
                        
                        ask_question "Please paste the PUBLIC KEY from above"
                        read -r new_pub_key
                        echo -en "${NC}"
                    fi
                    
                    rm -f "key_output_${timestamp}.tmp"
                    
                    if [ -n "$new_pub_key" ]; then
                        # Save public key to file
                        echo "$new_pub_key" > "client_manual_${timestamp}.public.key"
                        
                        echo -e "\n${GREEN}${BOLD}${ICON_SUCCESS} New client keys generated!${NC}"
                        print_double_line
                        echo -e "${CYAN}${BOLD}Files created:${NC}"
                        echo -e "  ${WHITE}Private Key:${NC} ${YELLOW}client_manual_${timestamp}.private.key${NC}"
                        echo -e "  ${WHITE}Public Key:${NC}  ${YELLOW}client_manual_${timestamp}.public.key${NC}"
                        print_double_line
                        
                        print_box "CLIENT PUBLIC KEY (Add to server)" "$new_pub_key"
                        
                        echo -e "${YELLOW}${BOLD}To use these keys:${NC}"
                        echo -e "${CYAN}1. Add this line to your client.toml:${NC}"
                        echo -e "   ${WHITE}private_key = \"client_manual_${timestamp}.private.key\"${NC}"
                        echo -e "${CYAN}2. Add public key to server's authorized_clients${NC}\n"
                    else
                        echo -e "${RED}${ICON_ERROR} Failed to generate keys!${NC}"
                    fi
                fi
                wait_for_enter
                ;;
            9)
                local socks_port=$(grep -A2 'protocol = "socks5"' "$INSTALL_DIR/client.toml" | grep "local_addr" | grep -oE ':[0-9]+' | grep -oE '[0-9]+' | head -1)
                if [ -z "$socks_port" ]; then
                    socks_port="1080"
                fi
                test_proxy_connection "$socks_port"
                ;;
            10)
                print_banner
                echo -e "${CYAN}${BOLD}${ICON_INFO} Get Shadowsocks Link${NC}\n"
                
                # Check if shadowsocks is configured
                if ! grep -q 'protocol = "shadowsocks"' "$INSTALL_DIR/client.toml"; then
                    echo -e "${RED}${ICON_ERROR} Shadowsocks is not configured in client.toml!${NC}"
                    echo -e "${YELLOW}Please enable Shadowsocks inbound first.${NC}"
                    wait_for_enter
                    continue
                fi
                
                cd "$INSTALL_DIR" || return
                
                echo -e "${BLUE}${ICON_GEAR} Generating Shadowsocks link...${NC}\n"
                
                # Run phoenix-client with -get-ss flag
                local ss_link=$(./phoenix-client -config client.toml -get-ss 2>&1)
                
                if [ -n "$ss_link" ] && [[ "$ss_link" == ss://* ]]; then
                    echo -e "${GREEN}${ICON_SUCCESS} Shadowsocks link generated successfully!${NC}\n"
                    print_double_line
                    echo -e "${CYAN}${BOLD}Shadowsocks Link:${NC}"
                    echo -e "${YELLOW}$ss_link${NC}"
                    print_double_line
                    echo -e "\n${CYAN}You can use this link in Shadowsocks clients.${NC}"
                else
                    echo -e "${RED}${ICON_ERROR} Failed to generate Shadowsocks link!${NC}"
                    echo -e "${YELLOW}Make sure:${NC}"
                    echo -e "  - Shadowsocks inbound is properly configured"
                    echo -e "  - Client is connected to the server"
                    echo -e "\n${YELLOW}Raw output:${NC}"
                    echo -e "$ss_link"
                fi
                
                wait_for_enter
                ;;
            11)
                print_banner
                echo -e "${CYAN}${BOLD}${ICON_GEAR} Rename Instance${NC}\n"
                echo -e "${YELLOW}Current instance: ${CYAN}$service_name${NC}"
                echo -e "${YELLOW}Current directory: ${CYAN}$INSTALL_DIR${NC}\n"
                
                ask_question "Enter new name (English only, e.g., iran1, tehran, home)"
                read -r new_name
                echo -en "${NC}"
                
                if [ -z "$new_name" ]; then
                    echo -e "${RED}${ICON_ERROR} Name cannot be empty!${NC}"
                    wait_for_enter
                    continue
                fi
                
                # Validate name
                if ! [[ "$new_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                    echo -e "${RED}${ICON_ERROR} Invalid name! Only English letters, numbers, hyphens, and underscores allowed.${NC}"
                    wait_for_enter
                    continue
                fi
                
                # Convert to lowercase
                new_name=$(echo "$new_name" | tr '[:upper:]' '[:lower:]')
                local new_instance_name="phoenix-${new_name}-client"
                local new_install_dir="${BASE_INSTALL_DIR}/${new_instance_name}"
                local new_service_file="/etc/systemd/system/${new_instance_name}.service"
                
                # Check if new name already exists
                if [ -d "$new_install_dir" ] || [ -f "$new_service_file" ]; then
                    echo -e "${RED}${ICON_ERROR} Instance with name '${new_instance_name}' already exists!${NC}"
                    wait_for_enter
                    continue
                fi
                
                echo -e "\n${YELLOW}Renaming to: ${CYAN}${new_instance_name}${NC}"
                
                ask_question "Confirm rename? (y/n)" "n"
                read -r confirm_rename
                echo -en "${NC}"
                
                if [[ "$confirm_rename" == "y" ]]; then
                    # Stop service
                    systemctl stop "$service_name"
                    systemctl disable "$service_name"
                    
                    # Rename directory
                    mv "$INSTALL_DIR" "$new_install_dir"
                    
                    # Update service file
                    sed -i "s|WorkingDirectory=.*|WorkingDirectory=$new_install_dir|g" "$SERVICE_FILE"
                    sed -i "s|ExecStart=.*|ExecStart=$new_install_dir/phoenix-client -config $new_install_dir/client.toml|g" "$SERVICE_FILE"
                    
                    # Rename service file
                    mv "$SERVICE_FILE" "$new_service_file"
                    
                    # Update variables
                    INSTALL_DIR="$new_install_dir"
                    SERVICE_FILE="$new_service_file"
                    
                    # Reload and start
                    systemctl daemon-reload
                    systemctl enable "$new_instance_name" --now
                    
                    echo -e "\n${GREEN}${ICON_SUCCESS} Instance renamed successfully!${NC}"
                    echo -e "${CYAN}New name: ${WHITE}${new_instance_name}${NC}"
                    echo -e "${CYAN}New directory: ${WHITE}${new_install_dir}${NC}"
                fi
                wait_for_enter
                ;;
            12) 
                ask_question "Uninstall Client? (y/n)" "n"
                read -r confirm
                echo -en "${NC}"
                if [[ "$confirm" == "y" ]]; then
                    systemctl stop "$service_name" && systemctl disable "$service_name"
                    rm -f "$SERVICE_FILE"
                    rm -rf "$INSTALL_DIR"
                    systemctl daemon-reload
                    echo -e "${GREEN}Client Removed.${NC}"; wait_for_enter; break
                fi
                ;;
            0) break ;;
        esac
    done
}

manage_server() {
    # Select instance to manage
    if ! select_instance "server" "manage"; then
        print_banner
        echo -e "${RED}${BOLD}${ICON_ERROR} Error: No Phoenix server instances found!${NC}"
        echo -e "${YELLOW}Please install a server first (Option 1).${NC}"
        wait_for_enter
        return
    fi
    
    if [ ! -f "$SERVICE_FILE" ]; then
        print_banner
        echo -e "${RED}${BOLD}${ICON_ERROR} Error: Selected instance is not properly installed!${NC}"
        wait_for_enter
        return
    fi

    while true; do
        print_banner
        echo -e "${BOLD}${MAGENTA}>> Management Menu:${NC}"
        echo -e "   1) ${BLUE}Service Status${NC}"
        echo -e "   2) ${GREEN}Show Server Info & Keys${NC}"
        echo -e "   3) ${BLUE}Real-time Logs${NC}"
        echo -e "   4) ${BLUE}Restart Service${NC}"
        echo -e "   5) ${BLUE}Edit Config (Nano)${NC}"
        echo -e "   6) ${CYAN}Add Client Public Key (mTLS)${NC}"
        echo -e "   7) ${YELLOW}Regenerate Server Keys${NC}"
        echo -e "   8) ${MAGENTA}Generate New Server Keys Manually${NC}"
        echo -e "   9) ${CYAN}Rename Instance${NC}"
        echo -e "  10) ${RED}Uninstall Phoenix${NC}"
        echo -e "   0) ${YELLOW}Back to Main${NC}"
        
        ask_question "Action" "0"
        read -r mgmt_act
        mgmt_act=${mgmt_act:-0}
        echo -en "${NC}"

        local service_name=$(get_service_name)
        
        case $mgmt_act in
            1) systemctl status "$service_name"; wait_for_enter ;;
            2)
                print_banner
                echo -e "${CYAN}${BOLD}${ICON_INFO} Server Information${NC}\n"
                
                # Get server IP
                local server_ip=$(hostname -I | awk '{print $1}')
                if [ -z "$server_ip" ]; then
                    server_ip=$(curl -s ifconfig.me 2>/dev/null || echo "Unable to detect")
                fi
                
                # Get listen port from config - improved regex
                local listen_port=$(grep "listen_addr" "$INSTALL_DIR/server.toml" | grep -oE ':[0-9]+' | grep -oE '[0-9]+' | head -1)
                if [ -z "$listen_port" ]; then
                    listen_port="Unknown"
                fi
                
                # Display server connection details in box
                echo -e "${CYAN}┌── Server Connection Details ──────────────────────────────┐${NC}"
                echo -e "  ${BOLD}${WHITE}Server IP:${NC}      ${CYAN}$server_ip${NC}"
                echo -e "  ${BOLD}${WHITE}Phoenix Port:${NC}   ${CYAN}$listen_port${NC}"
                echo -e "  ${BOLD}${WHITE}Connection:${NC}     ${CYAN}$server_ip:$listen_port${NC}"
                echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
                
                # Show public key if exists
                if [ -f "$INSTALL_DIR/server_public.key" ]; then
                    local pub_key=$(cat "$INSTALL_DIR/server_public.key")
                    echo -e "\n${GREEN}${BOLD}${ICON_KEY} Server Public Key:${NC}"
                    print_line
                    echo -e "${YELLOW}$pub_key${NC}"
                    print_line
                    echo -e "${CYAN}Copy this key to your client configuration${NC}\n"
                else
                    echo -e "\n${YELLOW}${ICON_INFO} No public key found. Server might be using NO TLS mode.${NC}\n"
                fi
                
                wait_for_enter
                ;;
            3) (trap 'exit' INT; journalctl -u "$service_name" -f -n 50 --no-hostname --output cat) ;;
            4) systemctl restart "$service_name"; echo -e "${GREEN}Restarted.${NC}"; sleep 1 ;;
            5) nano "$INSTALL_DIR/server.toml"; systemctl restart "$service_name" ;;
            6)
                print_banner
                echo -e "${CYAN}${BOLD}${ICON_KEY} Add Client Public Key for mTLS${NC}\n"
                
                ask_question "Enter CLIENT PUBLIC KEY"
                read -r new_client_key
                echo -en "${NC}"
                
                if [ -n "$new_client_key" ]; then
                    # Check if authorized_clients already exists
                    if grep -q "authorized_clients" "$INSTALL_DIR/server.toml"; then
                        # Add to existing array
                        sed -i "/authorized_clients = \[/a \  \"$new_client_key\"," "$INSTALL_DIR/server.toml"
                    else
                        # Create new array
                        cat >> "$INSTALL_DIR/server.toml" <<EOF

# mTLS: Authorized clients
authorized_clients = [
  "$new_client_key"
]
EOF
                    fi
                    
                    echo -e "\n${GREEN}${ICON_SUCCESS} Client key added successfully!${NC}"
                    
                    ask_question "Restart Phoenix service now? (y/n)" "y"
                    read -r restart_confirm
                    echo -en "${NC}"
                    
                    if [[ "$restart_confirm" == "y" ]]; then
                        systemctl restart "$service_name"
                        echo -e "${GREEN}${ICON_SUCCESS} Service restarted!${NC}"
                    fi
                fi
                wait_for_enter
                ;;
            7)
                print_banner
                echo -e "${YELLOW}${BOLD}${ICON_KEY} Regenerate Server Keys${NC}\n"
                echo -e "${RED}WARNING: This will generate new keys and restart the service!${NC}"
                echo -e "${YELLOW}All clients will need the new public key to reconnect.${NC}\n"
                
                ask_question "Continue? (y/n)" "n"
                read -r confirm_regen
                echo -en "${NC}"
                
                if [[ "$confirm_regen" == "y" ]]; then
                    cd "$INSTALL_DIR" || return
                    
                    # Backup old keys
                    [ -f "server.private.key" ] && mv server.private.key server.private.key.backup
                    [ -f "server_public.key" ] && mv server_public.key server_public.key.backup
                    
                    # Generate new keys
                    echo -e "${BLUE}${ICON_GEAR} Generating new keys...${NC}"
                    ./phoenix-server -gen-keys > key_output.tmp 2>&1
                    sleep 1
                    
                    # Extract new public key with improved method
                    local new_pub_key=$(grep -i "public key" key_output.tmp | grep -oE '[A-Za-z0-9+/=]{40,}' | head -n1)
                    
                    # Check for generated private key file
                    if [ -f "private.key" ]; then
                        mv -f private.key server.private.key
                        echo -e "${GREEN}${ICON_SUCCESS} Private key created${NC}"
                    elif [ -f "server_private.key" ]; then
                        mv -f server_private.key server.private.key
                        echo -e "${GREEN}${ICON_SUCCESS} Private key renamed to: server.private.key${NC}"
                    elif [ ! -f "server.private.key" ]; then
                        echo -e "${RED}${ICON_ERROR} Failed to generate private key!${NC}"
                        echo -e "${YELLOW}Raw output:${NC}"
                        cat key_output.tmp
                        rm -f key_output.tmp
                        wait_for_enter
                        return
                    fi
                    
                    # If public key extraction failed, ask for manual input
                    if [ -z "$new_pub_key" ]; then
                        echo -e "\n${YELLOW}${ICON_INFO} Could not auto-extract public key.${NC}"
                        echo -e "${YELLOW}Raw output:${NC}"
                        print_line
                        cat key_output.tmp
                        print_line
                        
                        ask_question "Please paste the PUBLIC KEY from above"
                        read -r new_pub_key
                        echo -en "${NC}"
                    fi
                    
                    rm -f key_output.tmp
                    
                    if [ -n "$new_pub_key" ]; then
                        # Save public key to file
                        echo "$new_pub_key" > server_public.key
                        
                        # Update config if needed
                        if ! grep -q "private_key" "$INSTALL_DIR/server.toml"; then
                            sed -i '/\[security\]/a private_key = "server.private.key"' "$INSTALL_DIR/server.toml"
                        fi
                        
                        echo -e "\n${GREEN}${ICON_SUCCESS} New keys generated!${NC}"
                        print_box "NEW SERVER PUBLIC KEY" "$new_pub_key"
                        echo -e "${YELLOW}${BOLD}Update this key on all your clients!${NC}\n"
                        
                        systemctl restart "$service_name"
                        echo -e "${GREEN}${ICON_SUCCESS} Service restarted with new keys${NC}"
                    else
                        echo -e "${RED}${ICON_ERROR} Failed to generate keys!${NC}"
                    fi
                fi
                wait_for_enter
                ;;
            8)
                print_banner
                echo -e "${MAGENTA}${BOLD}${ICON_KEY} Generate New Server Keys Manually${NC}\n"
                echo -e "${CYAN}This will generate a new key pair without modifying your config.${NC}"
                echo -e "${YELLOW}Use this if you want to create keys for a new server setup.${NC}\n"
                
                ask_question "Continue? (y/n)" "y"
                read -r confirm_gen
                echo -en "${NC}"
                
                if [[ "$confirm_gen" == "y" ]]; then
                    cd "$INSTALL_DIR" || return
                    
                    # Generate keys with timestamp to avoid conflicts
                    local timestamp=$(date +%s)
                    echo -e "${BLUE}${ICON_GEAR} Generating new keys...${NC}"
                    ./phoenix-server -gen-keys > "key_output_${timestamp}.tmp" 2>&1
                    sleep 1
                    
                    # Extract public key
                    local new_pub_key=$(grep -i "public key" "key_output_${timestamp}.tmp" | grep -oE '[A-Za-z0-9+/=]{40,}' | head -n1)
                    
                    # Check for generated private key file and rename with timestamp
                    if [ -f "private.key" ]; then
                        mv -f private.key "server_manual_${timestamp}.private.key"
                        echo -e "${GREEN}${ICON_SUCCESS} Private key saved as: server_manual_${timestamp}.private.key${NC}"
                    elif [ -f "server_private.key" ]; then
                        mv -f server_private.key "server_manual_${timestamp}.private.key"
                        echo -e "${GREEN}${ICON_SUCCESS} Private key saved as: server_manual_${timestamp}.private.key${NC}"
                    else
                        echo -e "${RED}${ICON_ERROR} Failed to generate private key!${NC}"
                        echo -e "${YELLOW}Raw output:${NC}"
                        cat "key_output_${timestamp}.tmp"
                        rm -f "key_output_${timestamp}.tmp"
                        wait_for_enter
                        continue
                    fi
                    
                    # If public key extraction failed, ask for manual input
                    if [ -z "$new_pub_key" ]; then
                        echo -e "\n${YELLOW}${ICON_INFO} Could not auto-extract public key.${NC}"
                        echo -e "${YELLOW}Raw output:${NC}"
                        print_line
                        cat "key_output_${timestamp}.tmp"
                        print_line
                        
                        ask_question "Please paste the PUBLIC KEY from above"
                        read -r new_pub_key
                        echo -en "${NC}"
                    fi
                    
                    rm -f "key_output_${timestamp}.tmp"
                    
                    if [ -n "$new_pub_key" ]; then
                        # Save public key to file
                        echo "$new_pub_key" > "server_manual_${timestamp}.public.key"
                        
                        echo -e "\n${GREEN}${BOLD}${ICON_SUCCESS} New server keys generated!${NC}"
                        print_double_line
                        echo -e "${CYAN}${BOLD}Files created:${NC}"
                        echo -e "  ${WHITE}Private Key:${NC} ${YELLOW}server_manual_${timestamp}.private.key${NC}"
                        echo -e "  ${WHITE}Public Key:${NC}  ${YELLOW}server_manual_${timestamp}.public.key${NC}"
                        print_double_line
                        
                        print_box "SERVER PUBLIC KEY (Add to clients)" "$new_pub_key"
                        
                        echo -e "${YELLOW}${BOLD}To use these keys:${NC}"
                        echo -e "${CYAN}1. Add this line to your server.toml [security] section:${NC}"
                        echo -e "   ${WHITE}private_key = \"server_manual_${timestamp}.private.key\"${NC}"
                        echo -e "${CYAN}2. Add public key to all client configs${NC}\n"
                    else
                        echo -e "${RED}${ICON_ERROR} Failed to generate keys!${NC}"
                    fi
                fi
                wait_for_enter
                ;;
            9)
                print_banner
                echo -e "${CYAN}${BOLD}${ICON_GEAR} Rename Instance${NC}\n"
                echo -e "${YELLOW}Current instance: ${CYAN}$service_name${NC}"
                echo -e "${YELLOW}Current directory: ${CYAN}$INSTALL_DIR${NC}\n"
                
                ask_question "Enter new name (English only, e.g., de, us, uk)"
                read -r new_name
                echo -en "${NC}"
                
                if [ -z "$new_name" ]; then
                    echo -e "${RED}${ICON_ERROR} Name cannot be empty!${NC}"
                    wait_for_enter
                    continue
                fi
                
                # Validate name
                if ! [[ "$new_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                    echo -e "${RED}${ICON_ERROR} Invalid name! Only English letters, numbers, hyphens, and underscores allowed.${NC}"
                    wait_for_enter
                    continue
                fi
                
                # Convert to lowercase
                new_name=$(echo "$new_name" | tr '[:upper:]' '[:lower:]')
                local new_instance_name="phoenix-${new_name}"
                local new_install_dir="${BASE_INSTALL_DIR}/${new_instance_name}"
                local new_service_file="/etc/systemd/system/${new_instance_name}.service"
                
                # Check if new name already exists
                if [ -d "$new_install_dir" ] || [ -f "$new_service_file" ]; then
                    echo -e "${RED}${ICON_ERROR} Instance with name '${new_instance_name}' already exists!${NC}"
                    wait_for_enter
                    continue
                fi
                
                echo -e "\n${YELLOW}Renaming to: ${CYAN}${new_instance_name}${NC}"
                
                ask_question "Confirm rename? (y/n)" "n"
                read -r confirm_rename
                echo -en "${NC}"
                
                if [[ "$confirm_rename" == "y" ]]; then
                    # Stop service
                    systemctl stop "$service_name"
                    systemctl disable "$service_name"
                    
                    # Rename directory
                    mv "$INSTALL_DIR" "$new_install_dir"
                    
                    # Update service file
                    sed -i "s|WorkingDirectory=.*|WorkingDirectory=$new_install_dir|g" "$SERVICE_FILE"
                    sed -i "s|ExecStart=.*|ExecStart=$new_install_dir/phoenix-server -config $new_install_dir/server.toml|g" "$SERVICE_FILE"
                    
                    # Rename service file
                    mv "$SERVICE_FILE" "$new_service_file"
                    
                    # Update variables
                    INSTALL_DIR="$new_install_dir"
                    SERVICE_FILE="$new_service_file"
                    
                    # Reload and start
                    systemctl daemon-reload
                    systemctl enable "$new_instance_name" --now
                    
                    echo -e "\n${GREEN}${ICON_SUCCESS} Instance renamed successfully!${NC}"
                    echo -e "${CYAN}New name: ${WHITE}${new_instance_name}${NC}"
                    echo -e "${CYAN}New directory: ${WHITE}${new_install_dir}${NC}"
                fi
                wait_for_enter
                ;;
            10) 
                ask_question "Uninstall? (y/n)" "n"
                read -r confirm
                echo -en "${NC}"
                if [[ "$confirm" == "y" ]]; then
                    systemctl stop "$service_name" && systemctl disable "$service_name"
                    rm -f "$SERVICE_FILE"
                    rm -rf "$INSTALL_DIR"
                    systemctl daemon-reload
                    echo -e "${GREEN}Removed.${NC}"; wait_for_enter; break
                fi
                ;;
            0) break ;;
        esac
    done
}

main() {
    check_root
    install_dependencies
    
    # First ask: Server or Client?
    while true; do
        print_banner
        echo -e "${BOLD}${MAGENTA}>> Installation Type:${NC}"
        echo -e "${CYAN}┌────────────────────────────────────────────────────────────┐${NC}"
        echo -e "  1) ${GREEN}${BOLD}${ICON_SERVER} Server (Kharej)${NC} - Install Phoenix Server"
        echo -e "  2) ${BLUE}${BOLD}${ICON_SHIELD} Client (Iran)${NC} - Install Phoenix Client"
        echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
        echo -e "  0) ${ICON_EXIT}  Exit"
        
        ask_question "Select Installation Type" "0"
        read -r install_type
        install_type=${install_type:-0}
        echo -en "${NC}"
        
        case $install_type in
            1)
                # Server Menu
                while true; do
                    print_banner
                    echo -e "${BOLD}${MAGENTA}>> Server (Kharej) Menu:${NC}"
                    echo -e "   1) ${ICON_DOWNLOAD}  Install / Reinstall Server"
                    echo -e "   2) ${ICON_GEAR}  Server Management"
                    echo -e "   0) ${ICON_EXIT}  Back"
                    
                    ask_question "Option" "0"
                    read -r server_opt
                    server_opt=${server_opt:-0}
                    echo -en "${NC}"

                    case $server_opt in
                        1) setup_server ;;
                        2) manage_server ;;
                        0) break ;;
                        *) sleep 1 ;;
                    esac
                done
                ;;
            2)
                # Client Menu
                while true; do
                    print_banner
                    echo -e "${BOLD}${MAGENTA}>> Client (Iran) Menu:${NC}"
                    echo -e "   1) ${ICON_DOWNLOAD}  Install / Reinstall Client"
                    echo -e "   2) ${ICON_GEAR}  Client Management"
                    echo -e "   0) ${ICON_EXIT}  Back"
                    
                    ask_question "Option" "0"
                    read -r client_opt
                    client_opt=${client_opt:-0}
                    echo -en "${NC}"

                    case $client_opt in
                        1) setup_client ;;
                        2) manage_client ;;
                        0) break ;;
                        *) sleep 1 ;;
                    esac
                done
                ;;
            0) 
                echo -e "\n${MAGENTA}${BOLD}Stay with Aura! ✨${NC}"
                return 0
                ;;
            *) sleep 1 ;;
        esac
    done
}

main
