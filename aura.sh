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
VERSION="v1.0.2"
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

    # Ask about fingerprint support BEFORE choosing TLS mode
    print_line
    echo -e "${BOLD}${MAGENTA}>> STEP 3: Fingerprint Spoofing Support${NC}"
    echo -e "${CYAN}┌────────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${BOLD}Do your clients need Fingerprint Spoofing?${NC}"
    echo -e ""
    echo -e "  ${GREEN}What is Fingerprint Spoofing?${NC}"
    echo -e "  Makes client connections look like real browsers"
    echo -e "  (Chrome/Firefox/Safari) to bypass DPI filtering."
    echo -e ""
    echo -e "  ${CYAN}Advantages:${NC}"
    echo -e "  ${GREEN}✓${NC} Bypass ISP Deep Packet Inspection (DPI)"
    echo -e "  ${GREEN}✓${NC} Harder to detect as VPN/Proxy"
    echo -e "  ${GREEN}✓${NC} Better for censored networks (Iran, China, etc.)"
    echo -e ""
    echo -e "  ${YELLOW}Disadvantages:${NC}"
    echo -e "  ${RED}✗${NC} Requires ECDSA key (slightly slower than Ed25519)"
    echo -e "  ${RED}✗${NC} Cannot use key pinning (server_public_key)"
    echo -e "  ${RED}✗${NC} Clients must use tls_mode=\"insecure\""
    echo -e ""
    echo -e "  ${BOLD}Recommendation:${NC}"
    echo -e "  ${GREEN}→ YES${NC} if deploying in Iran or censored countries"
    echo -e "  ${CYAN}→ NO${NC} if you want maximum security (mTLS)"
    echo -e ""
    echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
    
    ask_question "Enable Fingerprint Support? (y/n)" "y"
    read -r enable_fingerprint
    enable_fingerprint=${enable_fingerprint:-y}
    echo -en "${NC}"
    
    local key_type_choice="1"
    if [[ "$enable_fingerprint" == "y" ]]; then
        key_type_choice="2"
        echo -e "\n${GREEN}${ICON_SUCCESS} Fingerprint support enabled!${NC}"
        echo -e "${CYAN}Server will use ECDSA P256 key (compatible with fingerprint)${NC}"
    else
        echo -e "\n${BLUE}${ICON_INFO} Fingerprint support disabled.${NC}"
        echo -e "${CYAN}Server will use Ed25519 key (faster, more secure)${NC}"
    fi
    sleep 2

    # Setup Security
    print_line
    echo -e "${BOLD}${MAGENTA}>> STEP 4: Security Configuration${NC}"
    
    if [[ "$enable_fingerprint" == "y" ]]; then
        # Fingerprint enabled - only show compatible options
        echo -e "${CYAN}┌────────────────────────────────────────────────────────────┐${NC}"
        echo -e "  ${YELLOW}⚠️  Fingerprint Mode: Limited TLS Options${NC}"
        echo -e ""
        echo -e "  ${BOLD}Because you enabled Fingerprint Spoofing:${NC}"
        echo -e "  ${RED}✗${NC} One-Way TLS and mTLS are NOT compatible"
        echo -e "  ${RED}✗${NC} Chrome/Firefox/Safari don't support ECDSA with key pinning"
        echo -e "  ${GREEN}✓${NC} Only NO TLS and Insecure TLS work with fingerprint"
        echo -e ""
        echo -e "  ${BOLD}Available Options:${NC}"
        echo -e "  1) ${RED}${BOLD}NO TLS${NC} (Plain h2c - Not Recommended)"
        echo -e "     ${WHITE}└─${NC} No encryption, fingerprint meaningless"
        echo -e ""
        echo -e "  2) ${GREEN}${BOLD}Insecure TLS${NC} ${YELLOW}[Recommended for Fingerprint]${NC}"
        echo -e "     ${WHITE}├─${NC} Full TLS encryption"
        echo -e "     ${WHITE}├─${NC} Works perfectly with fingerprint"
        echo -e "     ${WHITE}└─${NC} Best for DPI bypass in Iran"
        echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
        
        ask_question "Selection (1 or 2)" "2"
        read -r sec_mode_input
        sec_mode_input=${sec_mode_input:-2}
        echo -en "${NC}"
        
        # Map to actual sec_mode values
        if [[ "$sec_mode_input" == "1" ]]; then
            sec_mode="1"  # NO TLS
        else
            sec_mode="2"  # Insecure TLS (but we'll handle it specially)
        fi
    else
        # No fingerprint - show all options
        echo -e "${CYAN}┌────────────────────────────────────────────────────────────┐${NC}"
        echo -e "  1) ${WHITE}${BOLD}NO TLS${NC} (Plain h2c - Not Recommended)"
        echo -e "  2) ${WHITE}${BOLD}One-Way TLS${NC} (HTTPS Style - Standard Security)"
        echo -e "  3) ${GREEN}${BOLD}mTLS (Mutual TLS)${NC} ${YELLOW}[Recommended - Highest Security]${NC}"
        echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
        
        ask_question "Selection" "3"
        read -r sec_mode
        sec_mode=${sec_mode:-3}
        echo -en "${NC}"
    fi

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
            echo -e "\n${BLUE}${ICON_KEY} ${BOLD}STEP 5: Generating Server Keys${NC}"
            cd "$INSTALL_DIR" || return
            
            if [[ "$key_type_choice" == "2" ]]; then
                # Generate ECDSA P256 key
                echo -e "${CYAN}Generating ECDSA P256 key (fingerprint-compatible)...${NC}"
                
                # Check if openssl is available
                if command -v openssl &> /dev/null; then
                    # Generate ECDSA key using openssl
                    openssl ecparam -genkey -name prime256v1 -noout -out server_ecdsa_temp.key 2>/dev/null
                    openssl pkcs8 -topk8 -nocrypt -in server_ecdsa_temp.key -out server.private.key 2>/dev/null
                    rm -f server_ecdsa_temp.key
                    chmod 600 server.private.key
                    
                    if [ -f "server.private.key" ]; then
                        echo -e "${GREEN}${ICON_SUCCESS} ECDSA P256 key generated successfully!${NC}"
                        echo -e "${GREEN}${ICON_SUCCESS} Key type: ECDSA P256 (compatible with fingerprint)${NC}"
                        server_pub_key="ECDSA_KEY_NO_PUBLIC_KEY_NEEDED"
                    else
                        echo -e "${RED}${ICON_ERROR} Failed to generate ECDSA key!${NC}"
                        echo -e "${YELLOW}Falling back to Ed25519...${NC}"
                        key_type_choice="1"
                    fi
                else
                    echo -e "${RED}${ICON_ERROR} OpenSSL not found!${NC}"
                    echo -e "${YELLOW}Installing OpenSSL...${NC}"
                    apt update && apt install -y openssl > /dev/null 2>&1
                    
                    # Try again
                    openssl ecparam -genkey -name prime256v1 -noout -out server_ecdsa_temp.key 2>/dev/null
                    openssl pkcs8 -topk8 -nocrypt -in server_ecdsa_temp.key -out server.private.key 2>/dev/null
                    rm -f server_ecdsa_temp.key
                    chmod 600 server.private.key
                    
                    if [ -f "server.private.key" ]; then
                        echo -e "${GREEN}${ICON_SUCCESS} ECDSA P256 key generated successfully!${NC}"
                        server_pub_key="ECDSA_KEY_NO_PUBLIC_KEY_NEEDED"
                    else
                        echo -e "${RED}${ICON_ERROR} Failed to generate ECDSA key!${NC}"
                        echo -e "${YELLOW}Falling back to Ed25519...${NC}"
                        key_type_choice="1"
                    fi
                fi
            fi
            
            if [[ "$key_type_choice" == "1" ]]; then
                # Generate Ed25519 key (default)
                echo -e "${CYAN}Generating Ed25519 key (default)...${NC}"
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
            fi

            # Add private key to server config
            sed -i '/\[security\]/a private_key = "server.private.key"' "$INSTALL_DIR/server.toml"
            
            # Display key information based on type
            if [[ "$key_type_choice" == "2" ]]; then
                # ECDSA key
                echo -e "\n${GREEN}${BOLD}${ICON_SUCCESS} ECDSA P256 Key Generated Successfully!${NC}"
                echo -e "${CYAN}┌────────────────────────────────────────────────────────────┐${NC}"
                echo -e "  ${BOLD}${WHITE}Key Type:${NC}        ${GREEN}ECDSA P256${NC}"
                echo -e "  ${BOLD}${WHITE}File:${NC}            ${CYAN}server.private.key${NC}"
                echo -e "  ${BOLD}${WHITE}Fingerprint:${NC}     ${GREEN}✅ Compatible${NC}"
                echo -e "  ${BOLD}${WHITE}Client Mode:${NC}     ${CYAN}tls_mode=\"insecure\" + fingerprint=\"chrome\"${NC}"
                echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
                
                echo -e "\n${YELLOW}${BOLD}Client Configuration:${NC}"
                echo -e "${CYAN}Your clients should use:${NC}"
                echo -e "${WHITE}  remote_addr = \"SERVER_IP:$port_num\"${NC}"
                echo -e "${WHITE}  tls_mode = \"insecure\"${NC}"
                echo -e "${WHITE}  fingerprint = \"chrome\"  ${GREEN}# This will work!${NC}"
                
                # Save key type info
                echo "ECDSA_P256" > "$INSTALL_DIR/server_key_type.txt"
            else
                # Ed25519 key
                # Save server public key to file for easy access
                echo "$server_pub_key" > "$INSTALL_DIR/server_public.key"
                
                echo -e "\n${GREEN}${BOLD}${ICON_SUCCESS} Ed25519 Key Generated Successfully!${NC}"
                print_box "SERVER PUBLIC KEY (Copy to client.toml)" "$server_pub_key"
                
                echo -e "${YELLOW}${BOLD}Client Configuration:${NC}"
                echo -e "${CYAN}Add this to your client.toml:${NC}"
                echo -e "${WHITE}server_public_key = \"$server_pub_key\"${NC}"
                echo -e "${RED}Note: Fingerprint NOT compatible with Ed25519${NC}\n"
                
                # Save key type info
                echo "ED25519" > "$INSTALL_DIR/server_key_type.txt"
            fi
            
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
    echo -e "${BOLD}${MAGENTA}>> STEP 2: Connection Type${NC}"
    echo -e "${CYAN}┌────────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${BOLD}Is your server behind CDN/Cloudflare?${NC}"
    echo -e "  1) ${GREEN}No${NC} - Direct connection to server IP"
    echo -e "  2) ${BLUE}Yes${NC} - Using domain with Cloudflare proxy"
    echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
    
    ask_question "Selection" "1"
    read -r connection_type
    connection_type=${connection_type:-1}
    echo -en "${NC}"
    
    if [[ "$connection_type" == "2" ]]; then
        # CDN/Cloudflare mode
        print_line
        echo -e "${BLUE}${ICON_INFO} ${BOLD}CDN/Cloudflare Mode${NC}"
        echo -e "${CYAN}You will use: tls_mode = \"system\"${NC}"
        echo -e "${YELLOW}Requirements:${NC}"
        echo -e "  - Domain name (not IP)"
        echo -e "  - Cloudflare proxy enabled (orange cloud)"
        echo -e "  - Server behind Cloudflare"
        echo -e ""
        
        ask_question "Continue with CDN mode? (y/n)" "y"
        read -r cdn_confirm
        echo -en "${NC}"
        
        if [[ "$cdn_confirm" != "y" ]]; then
            echo -e "${YELLOW}Switching to direct connection mode...${NC}"
            connection_type="1"
            sleep 2
        else
            sec_mode="5"  # Special mode for CDN
        fi
    fi
    
    if [[ "$connection_type" == "1" ]]; then
        # Direct connection - show TLS options
        print_line
        echo -e "${BOLD}${MAGENTA}>> STEP 2: Security Configuration (Direct Connection)${NC}"
        echo -e "${CYAN}┌────────────────────────────────────────────────────────────┐${NC}"
        echo -e "  ${BOLD}Choose TLS Mode:${NC}"
        echo -e ""
        echo -e "  1) ${RED}${BOLD}NO TLS${NC} (h2c - Plain HTTP/2)"
        echo -e "     ${WHITE}├─${NC} No encryption at all"
        echo -e "     ${WHITE}├─${NC} Fastest but ISP can see everything"
        echo -e "     ${WHITE}└─${NC} Use: Testing only or internal networks"
        echo -e ""
        echo -e "  2) ${YELLOW}${BOLD}Insecure TLS${NC} (HTTPS without cert verification)"
        echo -e "     ${WHITE}├─${NC} Full TLS encryption"
        echo -e "     ${WHITE}├─${NC} Works with self-signed certificates"
        echo -e "     ${WHITE}├─${NC} ${GREEN}✅ Works with Fingerprint Spoofing${NC}"
        echo -e "     ${WHITE}└─${NC} Use: DPI bypass + good security"
        echo -e ""
        echo -e "  3) ${CYAN}${BOLD}One-Way TLS${NC} (Key Pinning)"
        echo -e "     ${WHITE}├─${NC} Full TLS encryption + key verification"
        echo -e "     ${WHITE}├─${NC} Server authenticated by public key"
        echo -e "     ${WHITE}├─${NC} ${RED}❌ Fingerprint NOT compatible (Ed25519)${NC}"
        echo -e "     ${WHITE}└─${NC} Use: Good security without fingerprint"
        echo -e ""
        echo -e "  4) ${GREEN}${BOLD}mTLS${NC} (Mutual Authentication)"
        echo -e "     ${WHITE}├─${NC} Both server and client authenticated"
        echo -e "     ${WHITE}├─${NC} Anti-probing protection"
        echo -e "     ${WHITE}├─${NC} ${RED}❌ Fingerprint NOT compatible (Ed25519)${NC}"
        echo -e "     ${WHITE}└─${NC} Use: Maximum security, no fingerprint needed"
        echo -e ""
        echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
        echo -e "${BLUE}${ICON_INFO} Recommendation:${NC}"
        echo -e "  ${GREEN}Option 2 (Insecure TLS)${NC} - Best for Iran (DPI bypass with fingerprint)"
        echo -e "  ${GREEN}Option 4 (mTLS)${NC} - Best for maximum security (no fingerprint)"
        echo -e ""
        echo -e "${YELLOW}⚠️  Important:${NC}"
        echo -e "  ${WHITE}If your server has ECDSA key + fingerprint enabled:${NC}"
        echo -e "  ${WHITE}→ Use Option 2 (Insecure TLS) only${NC}"
        echo -e "  ${WHITE}→ Options 3 and 4 will NOT work with fingerprint${NC}"
        
        ask_question "Selection" "2"
        read -r sec_mode
        sec_mode=${sec_mode:-2}
        echo -en "${NC}"
    fi
    
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
        1)
            # NO TLS Mode
            print_line
            echo -e "${RED}${ICON_INFO} ${BOLD}NO TLS Mode (h2c)${NC}"
            echo -e "${YELLOW}Warning: No encryption! ISP can see all traffic.${NC}"
            echo -e "${CYAN}Use only for testing or internal networks.${NC}\n"
            # No tls_mode needed - default is h2c
            ;;
        2)
            # Insecure TLS Mode
            print_line
            echo -e "${YELLOW}${ICON_SHIELD} ${BOLD}Insecure TLS Mode${NC}"
            echo -e "${CYAN}✓ Full TLS encryption${NC}"
            echo -e "${CYAN}✓ Works with self-signed certificates${NC}"
            echo -e "${CYAN}✓ Best compatibility with Fingerprint Spoofing${NC}\n"
            
            # Add tls_mode to config
            cat >> "$INSTALL_DIR/client.toml" <<EOF
# TLS Mode: Insecure (skip certificate verification)
# Full encryption but no cert validation
tls_mode = "insecure"

EOF
            
            # Ask about fingerprint spoofing
            print_line
            echo -e "${MAGENTA}${ICON_SHIELD} ${BOLD}TLS Fingerprint Spoofing (Recommended!)${NC}"
            echo -e "${CYAN}┌────────────────────────────────────────────────────────────┐${NC}"
            echo -e "  ${BOLD}What is Fingerprint Spoofing?${NC}"
            echo -e "  Makes your connection look like a real browser (Chrome/Firefox)"
            echo -e "  to bypass ISP Deep Packet Inspection (DPI)."
            echo -e ""
            echo -e "  ${BOLD}Why use it?${NC}"
            echo -e "  ${GREEN}✓${NC} Bypass DPI filtering in Iran"
            echo -e "  ${GREEN}✓${NC} Harder to detect as VPN/Proxy"
            echo -e "  ${GREEN}✓${NC} Works perfectly with Insecure TLS mode"
            echo -e ""
            echo -e "  ${BOLD}Choose browser fingerprint:${NC}"
            echo -e "  1) ${GREEN}Chrome 120${NC} - Best compatibility (Recommended)"
            echo -e "  2) ${BLUE}Firefox 120${NC} - Good alternative"
            echo -e "  3) ${CYAN}Safari${NC} - For Apple-like fingerprint"
            echo -e "  4) ${YELLOW}Random${NC} - Different browser each connection"
            echo -e "  5) ${WHITE}None${NC} - Disable fingerprint spoofing"
            echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
            
            ask_question "Select fingerprint" "1"
            read -r fp_choice
            fp_choice=${fp_choice:-1}
            echo -en "${NC}"
            
            case $fp_choice in
                1) fingerprint="chrome" ;;
                2) fingerprint="firefox" ;;
                3) fingerprint="safari" ;;
                4) fingerprint="random" ;;
                *) fingerprint="" ;;
            esac
            
            if [ -n "$fingerprint" ]; then
                cat >> "$INSTALL_DIR/client.toml" <<EOF
# TLS Fingerprint: Impersonate browser to bypass DPI
fingerprint = "$fingerprint"

EOF
                echo -e "\n${GREEN}${ICON_SUCCESS} Fingerprint enabled: ${CYAN}$fingerprint${NC}"
                echo -e "${GREEN}${ICON_SUCCESS} Your connection will look like a real browser!${NC}"
            else
                echo -e "\n${YELLOW}${ICON_INFO} Fingerprint disabled${NC}"
            fi
            ;;
        3|4)
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
            
            # Ask about fingerprint spoofing for One-Way TLS and mTLS
            print_line
            echo -e "${RED}${ICON_SHIELD} ${BOLD}⚠️  TLS Fingerprint Spoofing - NOT RECOMMENDED${NC}"
            echo -e "${CYAN}┌────────────────────────────────────────────────────────────┐${NC}"
            echo -e "  ${BOLD}${RED}CRITICAL WARNING:${NC}"
            echo -e "  ${RED}✗${NC} Fingerprint does NOT work with One-Way TLS or mTLS"
            echo -e "  ${RED}✗${NC} Ed25519 keys are NOT compatible with browser fingerprints"
            echo -e "  ${RED}✗${NC} You WILL get: 'peer doesn't support signature algorithms'"
            echo -e ""
            echo -e "  ${BOLD}Why doesn't it work?${NC}"
            echo -e "  Chrome/Firefox/Safari fingerprints don't advertise Ed25519"
            echo -e "  as a valid server certificate algorithm."
            echo -e ""
            echo -e "  ${BOLD}${GREEN}Solution:${NC}"
            echo -e "  ${WHITE}If you need fingerprint spoofing:${NC}"
            echo -e "  1. Server: Enable fingerprint support (ECDSA key)"
            echo -e "  2. Client: Use Insecure TLS mode (not One-Way/mTLS)"
            echo -e "  3. Client: Enable fingerprint"
            echo -e ""
            echo -e "  ${BOLD}${YELLOW}For this setup (One-Way/mTLS):${NC}"
            echo -e "  ${GREEN}→${NC} Keep fingerprint DISABLED for stable connection"
            echo -e "  ${GREEN}→${NC} You still have full encryption + key pinning"
            echo -e ""
            echo -e "  ${BOLD}Do you still want to try fingerprint? (NOT recommended)${NC}"
            echo -e "  1) ${GREEN}No${NC} - Disable fingerprint (Recommended)"
            echo -e "  2) ${RED}Yes${NC} - Enable anyway (will likely fail)"
            echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
            
            ask_question "Selection" "1"
            read -r fp_choice
            fp_choice=${fp_choice:-1}
            echo -en "${NC}"
            
            if [[ "$fp_choice" == "2" ]]; then
                # User insists on trying fingerprint
                echo -e "\n${YELLOW}⚠️  You chose to enable fingerprint despite warnings.${NC}"
                echo -e "${YELLOW}Select browser (will likely fail):${NC}"
                echo -e "  1) Chrome"
                echo -e "  2) Firefox"
                echo -e "  3) Safari"
                echo -e "  4) Random"
                
                ask_question "Browser" "1"
                read -r browser_choice
                browser_choice=${browser_choice:-1}
                echo -en "${NC}"
                
                case $browser_choice in
                    1) fingerprint="chrome" ;;
                    2) fingerprint="firefox" ;;
                    3) fingerprint="safari" ;;
                    4) fingerprint="random" ;;
                    *) fingerprint="chrome" ;;
                esac
            else
                fingerprint=""
            fi
            
            if [ -n "$fingerprint" ]; then
                cat >> "$INSTALL_DIR/client.toml" <<EOF
# TLS Fingerprint: Impersonate browser (WILL FAIL with Ed25519)
fingerprint = "$fingerprint"

EOF
                echo -e "\n${YELLOW}${ICON_INFO} Fingerprint enabled: ${CYAN}$fingerprint${NC}"
                echo -e "${YELLOW}${ICON_INFO} If you get TLS errors, disable fingerprint!${NC}"
            else
                echo -e "\n${GREEN}${ICON_SUCCESS} Fingerprint disabled (stable connection)${NC}"
            fi
            
            if [[ "$sec_mode" == "4" ]]; then
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
        5)
            # CDN/Cloudflare Mode (System TLS)
            print_line
            echo -e "${BLUE}${ICON_SHIELD} ${BOLD}CDN/Cloudflare Mode (System TLS)${NC}"
            echo -e "${CYAN}Using OS certificate authorities for verification.${NC}\n"
            
            # Add tls_mode to config
            cat >> "$INSTALL_DIR/client.toml" <<EOF
# TLS Mode: System (use OS CA for verification)
# For connections through CDN/Cloudflare
tls_mode = "system"

EOF
            
            # Ask about fingerprint for CDN mode
            print_line
            echo -e "${MAGENTA}${ICON_SHIELD} ${BOLD}TLS Fingerprint Spoofing${NC}"
            echo -e "${CYAN}┌────────────────────────────────────────────────────────────┐${NC}"
            echo -e "  ${BOLD}Fingerprint with CDN/Cloudflare:${NC}"
            echo -e "  ${GREEN}✓${NC} Works well with System TLS mode"
            echo -e "  ${GREEN}✓${NC} Cloudflare handles certificates properly"
            echo -e "  ${GREEN}✓${NC} Recommended for DPI bypass"
            echo -e ""
            echo -e "  ${BOLD}Choose browser fingerprint:${NC}"
            echo -e "  1) ${GREEN}Chrome 120${NC} - Best compatibility (Recommended)"
            echo -e "  2) ${BLUE}Firefox 120${NC} - Good alternative"
            echo -e "  3) ${CYAN}Safari${NC} - For Apple-like fingerprint"
            echo -e "  4) ${YELLOW}Random${NC} - Different browser each connection"
            echo -e "  5) ${WHITE}None${NC} - No fingerprint spoofing"
            echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
            
            ask_question "Select fingerprint" "1"
            read -r fp_choice
            fp_choice=${fp_choice:-1}
            echo -en "${NC}"
            
            case $fp_choice in
                1) fingerprint="chrome" ;;
                2) fingerprint="firefox" ;;
                3) fingerprint="safari" ;;
                4) fingerprint="random" ;;
                *) fingerprint="" ;;
            esac
            
            if [ -n "$fingerprint" ]; then
                cat >> "$INSTALL_DIR/client.toml" <<EOF
# TLS Fingerprint: Impersonate browser
fingerprint = "$fingerprint"

EOF
                echo -e "\n${GREEN}${ICON_SUCCESS} Fingerprint enabled: ${CYAN}$fingerprint${NC}"
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

# Port Forward Management with Gost
manage_port_forward() {
    # Get current client instance name
    local current_instance=$(basename "$INSTALL_DIR")
    
    while true; do
        print_banner
        echo -e "${BOLD}${MAGENTA}>> Port Forward Management (Gost)${NC}\n"
        
        # List existing port forwards for this client only
        local pf_services=($(systemctl list-units --all --no-legend "gost-pf-${current_instance}-*.service" | awk '{print $1}'))
        
        if [ ${#pf_services[@]} -gt 0 ]; then
            echo -e "${CYAN}Active Port Forwards for this client:${NC}"
            for svc in "${pf_services[@]}"; do
                local status_icon="${RED}⚫${NC}"
                if systemctl is-active --quiet "$svc"; then
                    status_icon="${GREEN}●${NC}"
                fi
                
                # Extract port info from service name
                local pf_name=$(echo "$svc" | sed "s/gost-pf-${current_instance}-//;s/.service//")
                echo -e "  $status_icon ${CYAN}$pf_name${NC}"
            done
            echo ""
        else
            echo -e "${YELLOW}No port forwards configured for this client yet.${NC}\n"
        fi
        
        echo -e "${BOLD}${MAGENTA}Options:${NC}"
        echo -e "   1) ${GREEN}Add New Port Forward${NC}"
        echo -e "   2) ${BLUE}List Port Forwards${NC}"
        echo -e "   3) ${YELLOW}Stop Port Forward${NC}"
        echo -e "   4) ${GREEN}Start Port Forward${NC}"
        echo -e "   5) ${CYAN}View Port Forward Logs${NC}"
        echo -e "   6) ${RED}Remove Port Forward${NC}"
        echo -e "   0) ${YELLOW}Back${NC}"
        
        ask_question "Option" "0"
        read -r pf_opt
        pf_opt=${pf_opt:-0}
        echo -en "${NC}"
        
        case $pf_opt in
            1)
                add_port_forward
                ;;
            2)
                list_port_forwards
                ;;
            3)
                stop_port_forward
                ;;
            4)
                start_port_forward
                ;;
            5)
                view_port_forward_logs
                ;;
            6)
                remove_port_forward
                ;;
            0)
                break
                ;;
            *)
                sleep 1
                ;;
        esac
    done
}

add_port_forward() {
    print_banner
    echo -e "${GREEN}${BOLD}${ICON_GEAR} Add New Port Forward${NC}\n"
    
    # Check if gost is installed
    if ! command -v gost &> /dev/null; then
        echo -e "${YELLOW}${ICON_DOWNLOAD} Gost is not installed. Installing...${NC}\n"
        
        # Detect architecture
        local arch=$(detect_architecture)
        local gost_url=""
        
        if [ "$arch" == "amd64" ]; then
            gost_url="https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz"
        elif [ "$arch" == "arm64" ]; then
            gost_url="https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-armv8-2.11.5.gz"
        else
            echo -e "${RED}${ICON_ERROR} Unsupported architecture for gost!${NC}"
            wait_for_enter
            return
        fi
        
        # Download and install gost
        echo -e "${CYAN}Downloading from: ${gost_url}${NC}"
        if wget -q --spider "$gost_url" 2>/dev/null; then
            wget -q --show-progress "$gost_url" -O /tmp/gost.gz
            
            # Check if download was successful
            if [ ! -f /tmp/gost.gz ] || [ ! -s /tmp/gost.gz ]; then
                echo -e "${RED}${ICON_ERROR} Download failed!${NC}"
                rm -f /tmp/gost.gz
                wait_for_enter
                return
            fi
            
            gunzip -f /tmp/gost.gz
            
            # Check if gunzip was successful
            if [ ! -f /tmp/gost ]; then
                echo -e "${RED}${ICON_ERROR} Failed to extract gost!${NC}"
                rm -f /tmp/gost.gz
                wait_for_enter
                return
            fi
            
            chmod +x /tmp/gost
            mv /tmp/gost /usr/local/bin/gost
            
            echo -e "${GREEN}${ICON_SUCCESS} Gost installed successfully!${NC}\n"
        else
            echo -e "${RED}${ICON_ERROR} Failed to download gost from GitHub!${NC}"
            echo -e "${YELLOW}Trying alternative source...${NC}\n"
            
            # Try alternative source (direct binary without compression)
            local alt_url="https://sourceforge.net/projects/gost.mirror/files/v2.11.5/gost-linux-amd64-2.11.5.gz/download"
            if [ "$arch" == "arm64" ]; then
                alt_url="https://sourceforge.net/projects/gost.mirror/files/v2.11.5/gost-linux-armv8-2.11.5.gz/download"
            fi
            
            wget -q --show-progress "$alt_url" -O /tmp/gost.gz
            
            if [ ! -f /tmp/gost.gz ] || [ ! -s /tmp/gost.gz ]; then
                echo -e "${RED}${ICON_ERROR} Alternative download also failed!${NC}"
                echo -e "${YELLOW}Please install gost manually:${NC}"
                echo -e "${CYAN}wget https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz${NC}"
                echo -e "${CYAN}gunzip gost-linux-amd64-2.11.5.gz${NC}"
                echo -e "${CYAN}chmod +x gost-linux-amd64-2.11.5${NC}"
                echo -e "${CYAN}mv gost-linux-amd64-2.11.5 /usr/local/bin/gost${NC}"
                rm -f /tmp/gost.gz
                wait_for_enter
                return
            fi
            
            gunzip -f /tmp/gost.gz
            
            if [ ! -f /tmp/gost ]; then
                echo -e "${RED}${ICON_ERROR} Failed to extract gost!${NC}"
                rm -f /tmp/gost.gz
                wait_for_enter
                return
            fi
            
            chmod +x /tmp/gost
            mv /tmp/gost /usr/local/bin/gost
            
            echo -e "${GREEN}${ICON_SUCCESS} Gost installed successfully!${NC}\n"
        fi
    fi
    
    # Get SOCKS5 port from client config
    local socks_port=$(grep -A2 'protocol = "socks5"' "$INSTALL_DIR/client.toml" | grep "local_addr" | grep -oE ':[0-9]+' | grep -oE '[0-9]+' | head -1)
    
    if [ -z "$socks_port" ]; then
        echo -e "${RED}${ICON_ERROR} SOCKS5 proxy not found in client config!${NC}"
        echo -e "${YELLOW}Please make sure Phoenix client has SOCKS5 enabled.${NC}"
        wait_for_enter
        return
    fi
    
    # Get server IP from client config
    local server_addr=$(grep "^remote_addr" "$INSTALL_DIR/client.toml" | cut -d'"' -f2)
    local server_ip=$(echo "$server_addr" | cut -d':' -f1)
    
    if [ -z "$server_ip" ]; then
        echo -e "${RED}${ICON_ERROR} Server IP not found in client config!${NC}"
        wait_for_enter
        return
    fi
    
    echo -e "${CYAN}Phoenix SOCKS5 proxy: ${GREEN}127.0.0.1:$socks_port${NC}"
    echo -e "${CYAN}Target server IP: ${GREEN}$server_ip${NC}\n"
    print_line
    
    # Ask for single or multiple ports
    echo -e "${CYAN}${BOLD}Port Forward Mode:${NC}"
    echo -e "  ${WHITE}1)${NC} Single port forward"
    echo -e "  ${WHITE}2)${NC} Multiple ports forward (e.g., 9090,9091,9092)"
    echo ""
    ask_question "Select mode" "1"
    read -r port_mode
    port_mode=${port_mode:-1}
    echo -en "${NC}"
    
    local local_ports=()
    local dest_ports=()
    local gost_args=""
    
    if [ "$port_mode" == "2" ]; then
        # Multiple ports mode
        ask_question "Enter local ports (comma-separated, e.g., 9090,9091,9092)"
        read -r local_ports_input
        echo -en "${NC}"
        
        if [ -z "$local_ports_input" ]; then
            echo -e "${RED}${ICON_ERROR} Ports cannot be empty!${NC}"
            wait_for_enter
            return
        fi
        
        # Parse ports
        IFS=',' read -ra local_ports <<< "$local_ports_input"
        
        # Trim whitespace
        for i in "${!local_ports[@]}"; do
            local_ports[$i]=$(echo "${local_ports[$i]}" | xargs)
        done
        
        # Check if ports are valid and not in use
        for port in "${local_ports[@]}"; do
            if ! [[ "$port" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}${ICON_ERROR} Invalid port: $port${NC}"
                wait_for_enter
                return
            fi
            
            if is_port_in_use "$port"; then
                echo -e "${RED}${ICON_ERROR} Port $port is already in use!${NC}"
                wait_for_enter
                return
            fi
        done
        
        echo -e "${CYAN}${BOLD}Destination Port Mapping:${NC}"
        echo -e "  ${WHITE}1)${NC} Same ports (9090→9090, 9091→9091, 9092→9092)"
        echo -e "  ${WHITE}2)${NC} Custom ports (specify each destination port)"
        echo ""
        ask_question "Select mapping" "1"
        read -r mapping_mode
        mapping_mode=${mapping_mode:-1}
        echo -en "${NC}"
        
        if [ "$mapping_mode" == "1" ]; then
            # Same ports
            dest_ports=("${local_ports[@]}")
        else
            # Custom ports
            ask_question "Enter destination ports (comma-separated, same order as local ports)"
            read -r dest_ports_input
            echo -en "${NC}"
            
            if [ -z "$dest_ports_input" ]; then
                echo -e "${RED}${ICON_ERROR} Destination ports cannot be empty!${NC}"
                wait_for_enter
                return
            fi
            
            IFS=',' read -ra dest_ports <<< "$dest_ports_input"
            
            # Trim whitespace
            for i in "${!dest_ports[@]}"; do
                dest_ports[$i]=$(echo "${dest_ports[$i]}" | xargs)
            done
            
            # Check if count matches
            if [ ${#local_ports[@]} -ne ${#dest_ports[@]} ]; then
                echo -e "${RED}${ICON_ERROR} Number of local ports (${#local_ports[@]}) doesn't match destination ports (${#dest_ports[@]})!${NC}"
                wait_for_enter
                return
            fi
        fi
        
        # Build gost arguments for multiple ports (using server IP from config)
        for i in "${!local_ports[@]}"; do
            gost_args="$gost_args -L=tcp://0.0.0.0:${local_ports[$i]}/${server_ip}:${dest_ports[$i]}"
        done
        
    else
        # Single port mode
        ask_question "Enter local listen port (port to open on this server)"
        read -r local_port
        echo -en "${NC}"
        
        if [ -z "$local_port" ]; then
            echo -e "${RED}${ICON_ERROR} Local port cannot be empty!${NC}"
            wait_for_enter
            return
        fi
        
        # Check if port is already in use
        if is_port_in_use "$local_port"; then
            echo -e "${RED}${ICON_ERROR} Port $local_port is already in use!${NC}"
            wait_for_enter
            return
        fi
        
        ask_question "Enter destination port on server (target port on $server_ip)"
        read -r dest_port
        echo -en "${NC}"
        
        if [ -z "$dest_port" ]; then
            echo -e "${RED}${ICON_ERROR} Destination port cannot be empty!${NC}"
            wait_for_enter
            return
        fi
        
        local_ports=("$local_port")
        dest_ports=("$dest_port")
        gost_args="-L=tcp://0.0.0.0:${local_port}/${server_ip}:${dest_port}"
    fi
    
    ask_question "Enter a name for this forward (e.g., ssh, web, mysql)" "forward-${local_ports[0]}"
    read -r pf_name
    pf_name=${pf_name:-forward-${local_ports[0]}}
    echo -en "${NC}"
    
    # Validate name
    if ! [[ "$pf_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}${ICON_ERROR} Invalid name! Only English letters, numbers, hyphens, and underscores allowed.${NC}"
        wait_for_enter
        return
    fi
    
    # Get current client instance name
    local current_instance=$(basename "$INSTALL_DIR")
    
    local service_name="gost-pf-${current_instance}-${pf_name}"
    local service_file="/etc/systemd/system/${service_name}.service"
    
    # Check if service already exists
    if [ -f "$service_file" ]; then
        echo -e "${RED}${ICON_ERROR} Port forward with name '${pf_name}' already exists!${NC}"
        wait_for_enter
        return
    fi
    
    # Build description
    local description=""
    if [ ${#local_ports[@]} -eq 1 ]; then
        description="Gost Port Forward - ${pf_name} (${local_ports[0]} -> ${server_ip}:${dest_ports[0]})"
    else
        description="Gost Port Forward - ${pf_name} (${#local_ports[@]} ports)"
    fi
    
    # Create systemd service
    cat > "$service_file" <<EOF
[Unit]
Description=${description}
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/gost ${gost_args} -F=socks5://127.0.0.1:${socks_port}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable and start service
    systemctl daemon-reload
    systemctl enable "$service_name" --now > /dev/null 2>&1
    
    print_double_line
    echo -e "${GREEN}${BOLD}${ICON_SUCCESS} Port Forward Created Successfully!${NC}"
    print_double_line
    echo -e "${CYAN}${BOLD}Configuration:${NC}"
    echo -e "  ${WHITE}Name:${NC}        ${CYAN}${pf_name}${NC}"
    
    if [ ${#local_ports[@]} -eq 1 ]; then
        echo -e "  ${WHITE}Listen:${NC}      ${CYAN}0.0.0.0:${local_ports[0]}${NC}"
        echo -e "  ${WHITE}Forward to:${NC}  ${CYAN}${server_ip}:${dest_ports[0]}${NC}"
    else
        echo -e "  ${WHITE}Ports:${NC}       ${CYAN}${#local_ports[@]} ports${NC}"
        for i in "${!local_ports[@]}"; do
            echo -e "               ${CYAN}${local_ports[$i]} → ${server_ip}:${dest_ports[$i]}${NC}"
        done
    fi
    
    echo -e "  ${WHITE}Via SOCKS5:${NC}  ${CYAN}127.0.0.1:${socks_port}${NC}"
    echo -e "  ${WHITE}Service:${NC}     ${CYAN}${service_name}${NC}"
    print_double_line
    
    # Check if service started successfully
    sleep 1
    if systemctl is-active --quiet "$service_name"; then
        echo -e "${GREEN}${ICON_SUCCESS} Service is running!${NC}"
    else
        echo -e "${RED}${ICON_ERROR} Service failed to start!${NC}"
        echo -e "${YELLOW}Check logs with: journalctl -u ${service_name} -n 50${NC}"
    fi
    
    wait_for_enter
}

list_port_forwards() {
    print_banner
    echo -e "${CYAN}${BOLD}${ICON_INFO} Port Forward List${NC}\n"
    
    # Get current client instance name
    local current_instance=$(basename "$INSTALL_DIR")
    
    # List all port forward services for this client
    local pf_services=($(systemctl list-units --all --no-legend "gost-pf-${current_instance}-*.service" | awk '{print $1}'))
    
    if [ ${#pf_services[@]} -eq 0 ]; then
        echo -e "${YELLOW}No port forwards configured for this client.${NC}"
        wait_for_enter
        return
    fi
    
    echo -e "${CYAN}┌────────────────────────────────────────────────────────────┐${NC}"
    
    for svc in "${pf_services[@]}"; do
        local pf_name=$(echo "$svc" | sed 's/gost-pf-//;s/.service//')
        local service_file="/etc/systemd/system/${svc}"
        
        # Get status
        local status="${RED}INACTIVE${NC}"
        local status_icon="${RED}⚫${NC}"
        if systemctl is-active --quiet "$svc"; then
            status="${GREEN}ACTIVE${NC}"
            status_icon="${GREEN}●${NC}"
        fi
        
        # Extract config from service file
        if [ -f "$service_file" ]; then
            local description=$(grep "^Description=" "$service_file" | cut -d'=' -f2-)
            local exec_start=$(grep "^ExecStart=" "$service_file" | cut -d'=' -f2-)
            
            # Parse gost command - check for multiple -L flags
            local port_count=$(echo "$exec_start" | grep -o '\-L=tcp://' | wc -l)
            
            if [ "$port_count" -gt 1 ]; then
                # Multiple ports
                local socks=$(echo "$exec_start" | grep -oP 'socks5://\K[^[:space:]]+' | head -1)
                
                echo -e "  $status_icon ${BOLD}${WHITE}${pf_name}${NC} - $status"
                echo -e "     ${CYAN}Ports:${NC}       ${port_count} ports"
                
                # Extract all port mappings
                local mappings=$(echo "$exec_start" | grep -oP '0\.0\.0\.0:[0-9]+/[^[:space:]]+' | head -5)
                while IFS= read -r mapping; do
                    local local_p=$(echo "$mapping" | grep -oP '0\.0\.0\.0:\K[0-9]+')
                    local dest=$(echo "$mapping" | grep -oP '0\.0\.0\.0:[0-9]+/\K.+')
                    echo -e "                  ${CYAN}${local_p} → ${dest}${NC}"
                done <<< "$mappings"
                
                if [ "$port_count" -gt 5 ]; then
                    echo -e "                  ${YELLOW}... and $((port_count - 5)) more${NC}"
                fi
                
                echo -e "     ${CYAN}Via SOCKS5:${NC}  ${socks}"
                echo -e ""
            else
                # Single port
                local local_port=$(echo "$exec_start" | grep -oP '0\.0\.0\.0:\K[0-9]+' | head -1)
                local dest=$(echo "$exec_start" | grep -oP '0\.0\.0\.0:[0-9]+/\K[^[:space:]]+' | head -1)
                local socks=$(echo "$exec_start" | grep -oP 'socks5://\K[^[:space:]]+' | head -1)
                
                echo -e "  $status_icon ${BOLD}${WHITE}${pf_name}${NC} - $status"
                echo -e "     ${CYAN}Listen:${NC}      0.0.0.0:${local_port}"
                echo -e "     ${CYAN}Forward to:${NC}  ${dest}"
                echo -e "     ${CYAN}Via SOCKS5:${NC}  ${socks}"
                echo -e ""
            fi
        fi
    done
    
    echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
    wait_for_enter
}

stop_port_forward() {
    print_banner
    echo -e "${YELLOW}${BOLD}${ICON_GEAR} Stop Port Forward${NC}\n"
    
    # Get current client instance name
    local current_instance=$(basename "$INSTALL_DIR")
    
    local pf_services=($(systemctl list-units --all --no-legend "gost-pf-${current_instance}-*.service" | awk '{print $1}'))
    
    if [ ${#pf_services[@]} -eq 0 ]; then
        echo -e "${YELLOW}No port forwards configured for this client.${NC}"
        wait_for_enter
        return
    fi
    
    echo -e "${CYAN}Select port forward to stop:${NC}\n"
    
    local i=1
    for svc in "${pf_services[@]}"; do
        local pf_name=$(echo "$svc" | sed "s/gost-pf-${current_instance}-//;s/.service//")
        local status="${RED}INACTIVE${NC}"
        if systemctl is-active --quiet "$svc"; then
            status="${GREEN}ACTIVE${NC}"
        fi
        echo -e "  $i) ${CYAN}${pf_name}${NC} - $status"
        ((i++))
    done
    echo -e "  0) ${YELLOW}Cancel${NC}\n"
    
    ask_question "Select" "0"
    read -r choice
    choice=${choice:-0}
    echo -en "${NC}"
    
    if [ "$choice" == "0" ] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#pf_services[@]} ]; then
        return
    fi
    
    local selected_svc="${pf_services[$((choice-1))]}"
    
    systemctl stop "$selected_svc"
    echo -e "\n${GREEN}${ICON_SUCCESS} Port forward stopped: ${CYAN}${selected_svc}${NC}"
    wait_for_enter
}

start_port_forward() {
    print_banner
    echo -e "${GREEN}${BOLD}${ICON_GEAR} Start Port Forward${NC}\n"
    
    # Get current client instance name
    local current_instance=$(basename "$INSTALL_DIR")
    
    local pf_services=($(systemctl list-units --all --no-legend "gost-pf-${current_instance}-*.service" | awk '{print $1}'))
    
    if [ ${#pf_services[@]} -eq 0 ]; then
        echo -e "${YELLOW}No port forwards configured for this client.${NC}"
        wait_for_enter
        return
    fi
    
    echo -e "${CYAN}Select port forward to start:${NC}\n"
    
    local i=1
    for svc in "${pf_services[@]}"; do
        local pf_name=$(echo "$svc" | sed "s/gost-pf-${current_instance}-//;s/.service//")
        local status="${RED}INACTIVE${NC}"
        if systemctl is-active --quiet "$svc"; then
            status="${GREEN}ACTIVE${NC}"
        fi
        echo -e "  $i) ${CYAN}${pf_name}${NC} - $status"
        ((i++))
    done
    echo -e "  0) ${YELLOW}Cancel${NC}\n"
    
    ask_question "Select" "0"
    read -r choice
    choice=${choice:-0}
    echo -en "${NC}"
    
    if [ "$choice" == "0" ] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#pf_services[@]} ]; then
        return
    fi
    
    local selected_svc="${pf_services[$((choice-1))]}"
    
    systemctl start "$selected_svc"
    echo -e "\n${GREEN}${ICON_SUCCESS} Port forward started: ${CYAN}${selected_svc}${NC}"
    wait_for_enter
}

view_port_forward_logs() {
    print_banner
    echo -e "${CYAN}${BOLD}${ICON_INFO} View Port Forward Logs${NC}\n"
    
    # Get current client instance name
    local current_instance=$(basename "$INSTALL_DIR")
    
    local pf_services=($(systemctl list-units --all --no-legend "gost-pf-${current_instance}-*.service" | awk '{print $1}'))
    
    if [ ${#pf_services[@]} -eq 0 ]; then
        echo -e "${YELLOW}No port forwards configured for this client.${NC}"
        wait_for_enter
        return
    fi
    
    echo -e "${CYAN}Select port forward to view logs:${NC}\n"
    
    local i=1
    for svc in "${pf_services[@]}"; do
        local pf_name=$(echo "$svc" | sed "s/gost-pf-${current_instance}-//;s/.service//")
        local status="${RED}INACTIVE${NC}"
        if systemctl is-active --quiet "$svc"; then
            status="${GREEN}ACTIVE${NC}"
        fi
        echo -e "  $i) ${CYAN}${pf_name}${NC} - $status"
        ((i++))
    done
    echo -e "  0) ${YELLOW}Cancel${NC}\n"
    
    ask_question "Select" "0"
    read -r choice
    choice=${choice:-0}
    echo -en "${NC}"
    
    if [ "$choice" == "0" ] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#pf_services[@]} ]; then
        return
    fi
    
    local selected_svc="${pf_services[$((choice-1))]}"
    
    echo -e "\n${CYAN}Showing logs for: ${WHITE}${selected_svc}${NC}"
    echo -e "${YELLOW}Press Ctrl+C to exit${NC}\n"
    sleep 2
    
    (trap 'exit' INT; journalctl -u "$selected_svc" -f -n 50 --no-hostname --output cat)
}

remove_port_forward() {
    print_banner
    echo -e "${RED}${BOLD}${ICON_ERROR} Remove Port Forward${NC}\n"
    
    # Get current client instance name
    local current_instance=$(basename "$INSTALL_DIR")
    
    local pf_services=($(systemctl list-units --all --no-legend "gost-pf-${current_instance}-*.service" | awk '{print $1}'))
    
    if [ ${#pf_services[@]} -eq 0 ]; then
        echo -e "${YELLOW}No port forwards configured for this client.${NC}"
        wait_for_enter
        return
    fi
    
    echo -e "${CYAN}Select port forward to remove:${NC}\n"
    
    local i=1
    for svc in "${pf_services[@]}"; do
        local pf_name=$(echo "$svc" | sed "s/gost-pf-${current_instance}-//;s/.service//")
        local status="${RED}INACTIVE${NC}"
        if systemctl is-active --quiet "$svc"; then
            status="${GREEN}ACTIVE${NC}"
        fi
        echo -e "  $i) ${CYAN}${pf_name}${NC} - $status"
        ((i++))
    done
    echo -e "  0) ${YELLOW}Cancel${NC}\n"
    
    ask_question "Select" "0"
    read -r choice
    choice=${choice:-0}
    echo -en "${NC}"
    
    if [ "$choice" == "0" ] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#pf_services[@]} ]; then
        return
    fi
    
    local selected_svc="${pf_services[$((choice-1))]}"
    local service_file="/etc/systemd/system/${selected_svc}"
    
    echo -e "\n${RED}${BOLD}WARNING: This will permanently remove the port forward!${NC}"
    ask_question "Are you sure? (y/n)" "n"
    read -r confirm
    echo -en "${NC}"
    
    if [[ "$confirm" == "y" ]]; then
        systemctl stop "$selected_svc"
        systemctl disable "$selected_svc"
        rm -f "$service_file"
        systemctl daemon-reload
        
        echo -e "\n${GREEN}${ICON_SUCCESS} Port forward removed: ${CYAN}${selected_svc}${NC}"
    else
        echo -e "\n${YELLOW}Cancelled.${NC}"
    fi
    
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
        
        # Display current client info
        if [ -f "$INSTALL_DIR/client.toml" ]; then
            local client_name=$(basename "$INSTALL_DIR")
            local server_addr=$(grep "^remote_addr" "$INSTALL_DIR/client.toml" | cut -d'"' -f2)
            local server_ip=$(echo "$server_addr" | cut -d':' -f1)
            local server_port=$(echo "$server_addr" | cut -d':' -f2)
            local socks_port=$(grep -A2 'protocol = "socks5"' "$INSTALL_DIR/client.toml" | grep "local_addr" | grep -oE ':[0-9]+' | grep -oE '[0-9]+' | head -1)
            local tls_mode=$(grep "^tls_mode" "$INSTALL_DIR/client.toml" | cut -d'"' -f2)
            local fingerprint=$(grep "^fingerprint" "$INSTALL_DIR/client.toml" | cut -d'"' -f2)
            
            # Get port forwards info for this client
            local pf_services=($(systemctl list-units --all --no-legend "gost-pf-${client_name}-*.service" 2>/dev/null | awk '{print $1}'))
            local pf_count=${#pf_services[@]}
            
            echo -e "${CYAN}┌── Current Client ──────────────────────────────────────────┐${NC}"
            echo -e "  ${BOLD}${WHITE}Name:${NC}            ${CYAN}${client_name}${NC}"
            echo -e "  ${BOLD}${WHITE}Server IP:${NC}       ${CYAN}${server_ip}${NC}"
            echo -e "  ${BOLD}${WHITE}Server Port:${NC}     ${CYAN}${server_port}${NC}"
            
            if [ -n "$socks_port" ]; then
                echo -e "  ${BOLD}${WHITE}SOCKS5 Port:${NC}     ${CYAN}127.0.0.1:${socks_port}${NC}"
            fi
            
            # Show TLS mode - detect based on config
            local server_pub_key=$(grep "^server_public_key" "$INSTALL_DIR/client.toml" | cut -d'"' -f2)
            local client_priv_key=$(grep "^private_key" "$INSTALL_DIR/client.toml" | cut -d'"' -f2)
            
            if [ -n "$tls_mode" ]; then
                # Explicit TLS mode set
                case "$tls_mode" in
                    "insecure")
                        echo -e "  ${BOLD}${WHITE}TLS Mode:${NC}        ${YELLOW}Insecure TLS${NC}"
                        ;;
                    "system")
                        echo -e "  ${BOLD}${WHITE}TLS Mode:${NC}        ${YELLOW}System TLS (CDN)${NC}"
                        ;;
                    *)
                        echo -e "  ${BOLD}${WHITE}TLS Mode:${NC}        ${YELLOW}${tls_mode}${NC}"
                        ;;
                esac
            elif [ -n "$server_pub_key" ] && [ -n "$client_priv_key" ]; then
                # Both keys present = mTLS
                echo -e "  ${BOLD}${WHITE}TLS Mode:${NC}        ${GREEN}mTLS (Mutual Auth)${NC}"
            elif [ -n "$server_pub_key" ]; then
                # Only server key = One-Way TLS
                echo -e "  ${BOLD}${WHITE}TLS Mode:${NC}        ${YELLOW}One-Way TLS${NC}"
            else
                # No TLS mode and no keys = h2c
                echo -e "  ${BOLD}${WHITE}TLS Mode:${NC}        ${YELLOW}h2c (no TLS)${NC}"
            fi
            
            # Show fingerprint
            if [ -n "$fingerprint" ]; then
                echo -e "  ${BOLD}${WHITE}Fingerprint:${NC}     ${GREEN}${fingerprint}${NC}"
            else
                echo -e "  ${BOLD}${WHITE}Fingerprint:${NC}     ${YELLOW}disabled${NC}"
            fi
            
            # Show port forwards with details
            if [ "$pf_count" -gt 0 ]; then
                echo -e "  ${BOLD}${WHITE}Port Forwards:${NC}   ${GREEN}${pf_count} active${NC}"
                
                # Show first 3 port forwards with details
                local shown=0
                for svc in "${pf_services[@]}"; do
                    if [ $shown -ge 3 ]; then
                        break
                    fi
                    
                    local pf_name=$(echo "$svc" | sed "s/gost-pf-${client_name}-//;s/.service//")
                    local service_file="/etc/systemd/system/${svc}"
                    
                    if [ -f "$service_file" ]; then
                        local exec_start=$(grep "^ExecStart=" "$service_file" | cut -d'=' -f2-)
                        local port_count=$(echo "$exec_start" | grep -o '\-L=tcp://' | wc -l)
                        
                        if [ "$port_count" -eq 1 ]; then
                            # Single port
                            local local_port=$(echo "$exec_start" | grep -oP '0\.0\.0\.0:\K[0-9]+' | head -1)
                            local dest=$(echo "$exec_start" | grep -oP '0\.0\.0\.0:[0-9]+/\K[^[:space:]]+' | head -1)
                            echo -e "                   ${CYAN}├─ ${pf_name}: ${local_port}→${dest}${NC}"
                        else
                            # Multiple ports
                            echo -e "                   ${CYAN}├─ ${pf_name}: ${port_count} ports${NC}"
                        fi
                        ((shown++))
                    fi
                done
                
                if [ "$pf_count" -gt 3 ]; then
                    echo -e "                   ${YELLOW}└─ ... and $((pf_count - 3)) more${NC}"
                fi
            else
                echo -e "  ${BOLD}${WHITE}Port Forwards:${NC}   ${YELLOW}none${NC}"
            fi
            
            echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
            echo ""
        fi
        
        echo -e "${BOLD}${MAGENTA}>> Client Management Menu:${NC}"
        echo -e "   1) ${BLUE}Service Status${NC}"
        echo -e "   2) ${GREEN}Show Client Info & Keys${NC}"
        echo -e "   3) ${BLUE}Real-time Logs${NC}"
        echo -e "   4) ${BLUE}Restart Service${NC}"
        echo -e "   5) ${BLUE}Edit Config (Nano)${NC}"
        echo -e "   6) ${CYAN}Update Server Public Key${NC}"
        echo -e "   7) ${YELLOW}Regenerate Client Keys (mTLS)${NC}"
        echo -e "   8) ${MAGENTA}Generate New Client Keys Manually${NC}"
        echo -e "   9) ${CYAN}Configure TLS Fingerprint (Anti-DPI)${NC}"
        echo -e "  10) ${GREEN}Test Proxy Connection${NC}"
        echo -e "  11) ${CYAN}Get Shadowsocks Link${NC}"
        echo -e "  12) ${MAGENTA}Port Forward Management (Gost)${NC}"
        echo -e "  13) ${CYAN}Rename Instance${NC}"
        echo -e "  14) ${RED}Uninstall Client${NC}"
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
                
                # Extract server IP and port separately
                local server_ip=$(echo "$server_addr" | cut -d':' -f1)
                local server_port=$(echo "$server_addr" | cut -d':' -f2)
                
                # Get local ports with improved extraction
                local socks_port=$(grep -A2 'protocol = "socks5"' "$INSTALL_DIR/client.toml" | grep "local_addr" | grep -oE ':[0-9]+' | grep -oE '[0-9]+' | head -1)
                local ssh_port=$(grep -A2 'protocol = "ssh"' "$INSTALL_DIR/client.toml" | grep "local_addr" | grep -oE ':[0-9]+' | grep -oE '[0-9]+' | head -1)
                local ss_port=$(grep -A2 'protocol = "shadowsocks"' "$INSTALL_DIR/client.toml" | grep "local_addr" | grep -oE ':[0-9]+' | grep -oE '[0-9]+' | head -1)
                
                # Display client configuration in box
                echo -e "${CYAN}┌── Client Configuration ────────────────────────────────────┐${NC}"
                echo -e "  ${BOLD}${WHITE}Server IP:${NC}       ${CYAN}$server_ip${NC}"
                echo -e "  ${BOLD}${WHITE}Server Port:${NC}     ${CYAN}$server_port${NC}"
                
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
                
                # Show TLS mode if configured
                local tls_mode=$(grep "^tls_mode" "$INSTALL_DIR/client.toml" | cut -d'"' -f2)
                if [ -n "$tls_mode" ]; then
                    echo -e "\n${CYAN}${BOLD}${ICON_SHIELD} TLS Mode:${NC} ${YELLOW}$tls_mode${NC}"
                fi
                
                # Show fingerprint if configured
                local fingerprint=$(grep "^fingerprint" "$INSTALL_DIR/client.toml" | cut -d'"' -f2)
                if [ -n "$fingerprint" ]; then
                    echo -e "${CYAN}${BOLD}${ICON_SHIELD} TLS Fingerprint:${NC} ${YELLOW}$fingerprint${NC} ${GREEN}(Anti-DPI Active)${NC}"
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
                print_banner
                echo -e "${MAGENTA}${BOLD}${ICON_SHIELD} Configure TLS Fingerprint (Anti-DPI)${NC}\n"
                echo -e "${CYAN}TLS Fingerprint Spoofing helps bypass ISP Deep Packet Inspection.${NC}"
                echo -e "${CYAN}It impersonates browser TLS handshakes to avoid detection.${NC}\n"
                
                # Show current fingerprint
                local current_fp=$(grep "^fingerprint" "$INSTALL_DIR/client.toml" | cut -d'"' -f2)
                if [ -n "$current_fp" ]; then
                    echo -e "${YELLOW}Current fingerprint: ${CYAN}$current_fp${NC}\n"
                else
                    echo -e "${YELLOW}Current: ${CYAN}None (Go default)${NC}\n"
                fi
                
                echo -e "${CYAN}┌────────────────────────────────────────────────────────────┐${NC}"
                echo -e "  Select TLS Fingerprint:"
                echo -e "  1) ${GREEN}Chrome${NC} - Chrome 120 (Recommended)"
                echo -e "  2) ${BLUE}Firefox${NC} - Firefox 120"
                echo -e "  3) ${CYAN}Safari${NC} - Safari browser"
                echo -e "  4) ${YELLOW}Random${NC} - Random browser per connection"
                echo -e "  5) ${WHITE}None${NC} - Disable fingerprint spoofing"
                echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
                
                ask_question "Select fingerprint" "1"
                read -r fp_choice
                fp_choice=${fp_choice:-1}
                echo -en "${NC}"
                
                local new_fingerprint=""
                case $fp_choice in
                    1) new_fingerprint="chrome" ;;
                    2) new_fingerprint="firefox" ;;
                    3) new_fingerprint="safari" ;;
                    4) new_fingerprint="random" ;;
                    5) new_fingerprint="" ;;
                    *) new_fingerprint="chrome" ;;
                esac
                
                # Update or add fingerprint in config
                if grep -q "^fingerprint" "$INSTALL_DIR/client.toml"; then
                    if [ -n "$new_fingerprint" ]; then
                        # Update existing fingerprint
                        sed -i "s|^fingerprint = \".*\"|fingerprint = \"$new_fingerprint\"|" "$INSTALL_DIR/client.toml"
                        echo -e "\n${GREEN}${ICON_SUCCESS} Fingerprint updated to: ${CYAN}$new_fingerprint${NC}"
                    else
                        # Remove fingerprint line
                        sed -i '/^fingerprint = /d' "$INSTALL_DIR/client.toml"
                        echo -e "\n${GREEN}${ICON_SUCCESS} Fingerprint spoofing disabled${NC}"
                    fi
                else
                    if [ -n "$new_fingerprint" ]; then
                        # Add new fingerprint after server_public_key or remote_addr
                        if grep -q "^server_public_key" "$INSTALL_DIR/client.toml"; then
                            sed -i "/^server_public_key/a fingerprint = \"$new_fingerprint\"" "$INSTALL_DIR/client.toml"
                        else
                            sed -i "/^remote_addr/a \n# TLS Fingerprint Spoofing\nfingerprint = \"$new_fingerprint\"" "$INSTALL_DIR/client.toml"
                        fi
                        echo -e "\n${GREEN}${ICON_SUCCESS} Fingerprint set to: ${CYAN}$new_fingerprint${NC}"
                    else
                        echo -e "\n${YELLOW}${ICON_INFO} No fingerprint configured${NC}"
                    fi
                fi
                
                ask_question "Restart Phoenix Client service now? (y/n)" "y"
                read -r restart_confirm
                echo -en "${NC}"
                
                if [[ "$restart_confirm" == "y" ]]; then
                    systemctl restart "$service_name"
                    echo -e "${GREEN}${ICON_SUCCESS} Service restarted!${NC}"
                fi
                wait_for_enter
                ;;
            10)
                local socks_port=$(grep -A2 'protocol = "socks5"' "$INSTALL_DIR/client.toml" | grep "local_addr" | grep -oE ':[0-9]+' | grep -oE '[0-9]+' | head -1)
                if [ -z "$socks_port" ]; then
                    socks_port="1080"
                fi
                test_proxy_connection "$socks_port"
                ;;
            11)
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
            12)
                manage_port_forward
                ;;
            13)
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
            14) 
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
                
                # Check key type
                local key_type="Unknown"
                local key_type_display=""
                local fingerprint_compatible="Unknown"
                local client_recommendation=""
                
                if [ -f "$INSTALL_DIR/server_key_type.txt" ]; then
                    key_type=$(cat "$INSTALL_DIR/server_key_type.txt")
                    if [ "$key_type" == "ECDSA_P256" ]; then
                        key_type_display="${GREEN}ECDSA P256${NC} (Fingerprint Compatible)"
                        fingerprint_compatible="${GREEN}✅ YES${NC}"
                        client_recommendation="${CYAN}tls_mode=\"insecure\" + fingerprint=\"chrome\"${NC}"
                    elif [ "$key_type" == "ED25519" ]; then
                        key_type_display="${YELLOW}Ed25519${NC} (Faster, More Secure)"
                        fingerprint_compatible="${RED}❌ NO${NC}"
                        client_recommendation="${CYAN}server_public_key=\"...\" (no fingerprint)${NC}"
                    fi
                else
                    # Try to detect from key file
                    if [ -f "$INSTALL_DIR/server.private.key" ]; then
                        if grep -q "BEGIN EC PRIVATE KEY" "$INSTALL_DIR/server.private.key" 2>/dev/null || \
                           (openssl pkey -in "$INSTALL_DIR/server.private.key" -text -noout 2>/dev/null | grep -q "prime256v1"); then
                            key_type="ECDSA_P256"
                            key_type_display="${GREEN}ECDSA P256${NC} (Fingerprint Compatible)"
                            fingerprint_compatible="${GREEN}✅ YES${NC}"
                            client_recommendation="${CYAN}tls_mode=\"insecure\" + fingerprint=\"chrome\"${NC}"
                        else
                            key_type="ED25519"
                            key_type_display="${YELLOW}Ed25519${NC} (Faster, More Secure)"
                            fingerprint_compatible="${RED}❌ NO${NC}"
                            client_recommendation="${CYAN}server_public_key=\"...\" (no fingerprint)${NC}"
                        fi
                    fi
                fi
                
                # Display server connection details in box
                echo -e "${CYAN}┌── Server Connection Details ──────────────────────────────┐${NC}"
                echo -e "  ${BOLD}${WHITE}Server IP:${NC}      ${CYAN}$server_ip${NC}"
                echo -e "  ${BOLD}${WHITE}Phoenix Port:${NC}   ${CYAN}$listen_port${NC}"
                echo -e "  ${BOLD}${WHITE}Connection:${NC}     ${CYAN}$server_ip:$listen_port${NC}"
                echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
                
                # Display key information
                echo -e "\n${CYAN}┌── Server Key Information ─────────────────────────────────┐${NC}"
                echo -e "  ${BOLD}${WHITE}Key Type:${NC}                $key_type_display"
                echo -e "  ${BOLD}${WHITE}Fingerprint Compatible:${NC}  $fingerprint_compatible"
                echo -e "  ${BOLD}${WHITE}Key File:${NC}                ${CYAN}server.private.key${NC}"
                echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
                
                # Show public key if exists (Ed25519 only)
                if [ "$key_type" == "ED25519" ] && [ -f "$INSTALL_DIR/server_public.key" ]; then
                    local pub_key=$(cat "$INSTALL_DIR/server_public.key")
                    echo -e "\n${GREEN}${BOLD}${ICON_KEY} Server Public Key (Ed25519):${NC}"
                    print_line
                    echo -e "${YELLOW}$pub_key${NC}"
                    print_line
                fi
                
                # Client configuration recommendation
                echo -e "\n${CYAN}┌── Client Configuration Recommendation ────────────────────┐${NC}"
                if [ "$key_type" == "ECDSA_P256" ]; then
                    echo -e "  ${BOLD}${GREEN}For Fingerprint Spoofing (DPI Bypass):${NC}"
                    echo -e "  ${WHITE}remote_addr = \"$server_ip:$listen_port\"${NC}"
                    echo -e "  ${WHITE}tls_mode = \"insecure\"${NC}"
                    echo -e "  ${WHITE}fingerprint = \"chrome\"  ${GREEN}# Recommended${NC}"
                    echo -e ""
                    echo -e "  ${BOLD}${CYAN}Or without Fingerprint:${NC}"
                    echo -e "  ${WHITE}remote_addr = \"$server_ip:$listen_port\"${NC}"
                    echo -e "  ${WHITE}tls_mode = \"insecure\"${NC}"
                    echo -e "  ${WHITE}# No fingerprint line${NC}"
                elif [ "$key_type" == "ED25519" ]; then
                    echo -e "  ${BOLD}${GREEN}For Key Pinning (Secure):${NC}"
                    echo -e "  ${WHITE}remote_addr = \"$server_ip:$listen_port\"${NC}"
                    if [ -f "$INSTALL_DIR/server_public.key" ]; then
                        local pub_key=$(cat "$INSTALL_DIR/server_public.key")
                        echo -e "  ${WHITE}server_public_key = \"$pub_key\"${NC}"
                    else
                        echo -e "  ${WHITE}server_public_key = \"YOUR_SERVER_PUBLIC_KEY\"${NC}"
                    fi
                    echo -e "  ${RED}# Do NOT use fingerprint with Ed25519${NC}"
                    echo -e ""
                    echo -e "  ${BOLD}${YELLOW}Or Insecure TLS (without key pinning):${NC}"
                    echo -e "  ${WHITE}remote_addr = \"$server_ip:$listen_port\"${NC}"
                    echo -e "  ${WHITE}tls_mode = \"insecure\"${NC}"
                    echo -e "  ${RED}# Do NOT use fingerprint with Ed25519${NC}"
                else
                    echo -e "  ${YELLOW}Unable to determine key type${NC}"
                    echo -e "  ${WHITE}Check server.toml and key files manually${NC}"
                fi
                echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
                
                echo -e "\n${BLUE}${ICON_INFO} Tip: Use Aura script on client to configure automatically${NC}\n"
                
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
