#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}Fatal error: ${plain} Please run this script with root privilege \n " && exit 1

# Check OS and set release variable
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "Failed to check the system OS, please contact the author!" >&2
    exit 1
fi
echo "The OS release is: $release"

arch() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    i*86 | x86) echo '386' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    armv7* | armv7 | arm) echo 'armv7' ;;
    armv6* | armv6) echo 'armv6' ;;
    armv5* | armv5) echo 'armv5' ;;
    s390x) echo 's390x' ;;
    *) echo -e "${green}Unsupported CPU architecture! ${plain}" && rm -f install.sh && exit 1 ;;
    esac
}

echo "Arch: $(arch)"

check_glibc_version() {
    glibc_version=$(ldd --version | head -n1 | awk '{print $NF}')
    
    required_version="2.32"
    if [[ "$(printf '%s\n' "$required_version" "$glibc_version" | sort -V | head -n1)" != "$required_version" ]]; then
        echo -e "${red}GLIBC version $glibc_version is too old! Required: 2.32 or higher${plain}"
        echo "Please upgrade to a newer version of your operating system to get a higher GLIBC version."
        exit 1
    fi
    echo "GLIBC version: $glibc_version (meets requirement of 2.32+)"
}
check_glibc_version

install_base() {
    case "${release}" in
    ubuntu | debian | armbian)
        apt-get update && apt-get install -y -q wget curl tar tzdata
        ;;
    centos | rhel | almalinux | rocky | ol)
        yum -y update && yum install -y -q wget curl tar tzdata
        ;;
    fedora | amzn | virtuozzo)
        dnf -y update && dnf install -y -q wget curl tar tzdata
        ;;
    arch | manjaro | parch)
        pacman -Syu && pacman -Syu --noconfirm wget curl tar tzdata
        ;;
    opensuse-tumbleweed)
        zypper refresh && zypper -q install -y wget curl tar timezone
        ;;
    *)
        apt-get update && apt install -y -q wget curl tar tzdata
        ;;
    esac
}

gen_random_string() {
    local length="$1"
    local random_string=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1)
    echo "$random_string"
}

config_after_install() {
    # Check if x-ui binary exists and is executable
    if [ ! -f "/usr/local/x-ui/x-ui" ] || [ ! -x "/usr/local/x-ui/x-ui" ]; then
        echo -e "${red}Error: x-ui binary not found or not executable${plain}"
        return 1
    fi
    
    # Try to get current settings, with error handling
    local existing_hasDefaultCredential=""
    local existing_webBasePath=""
    local existing_port=""
    
    # Get server IP
    local server_ip=$(curl -s --max-time 3 https://api.ipify.org)
    if [ -z "$server_ip" ]; then
        server_ip=$(curl -s --max-time 3 https://4.ident.me)
    fi
    
    # Try to get current settings
    if /usr/local/x-ui/x-ui setting -show true >/dev/null 2>&1; then
        existing_hasDefaultCredential=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'hasDefaultCredential: .+' | awk '{print $2}' 2>/dev/null || echo "")
        existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}' 2>/dev/null || echo "")
        existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}' 2>/dev/null || echo "")
    else
        echo -e "${yellow}Warning: Could not read current settings, will use defaults${plain}"
        existing_hasDefaultCredential="true"
        existing_webBasePath=""
        existing_port="54321"
    fi

    if [[ ${#existing_webBasePath} -lt 4 ]]; then
        if [[ "$existing_hasDefaultCredential" == "true" ]]; then
            local config_webBasePath=$(gen_random_string 15)
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)

            read -rp "Would you like to customize the Panel Port settings? (If not, a random port will be applied) [y/n]: " config_confirm
            if [[ "${config_confirm}" == "y" || "${config_confirm}" == "Y" ]]; then
                read -rp "Please set up the panel port: " config_port
                echo -e "${yellow}Your Panel Port is: ${config_port}${plain}"
            else
                local config_port=$(shuf -i 1024-62000 -n 1)
                echo -e "${yellow}Generated random port: ${config_port}${plain}"
            fi

            if /usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}" -port "${config_port}" -webBasePath "${config_webBasePath}" >/dev/null 2>&1; then
                echo -e "This is a fresh installation, generating random login info for security concerns:"
                echo -e "###############################################"
                echo -e "${green}Username: ${config_username}${plain}"
                echo -e "${green}Password: ${config_password}${plain}"
                echo -e "${green}Port: ${config_port}${plain}"
                echo -e "${green}WebBasePath: ${config_webBasePath}${plain}"
                echo -e "${green}Access URL: http://${server_ip}:${config_port}/${config_webBasePath}${plain}"
                echo -e "###############################################"
            else
                echo -e "${red}Error: Failed to configure x-ui settings${plain}"
                return 1
            fi
        else
            local config_webBasePath=$(gen_random_string 15)
            echo -e "${yellow}WebBasePath is missing or too short. Generating a new one...${plain}"
            if /usr/local/x-ui/x-ui setting -webBasePath "${config_webBasePath}" >/dev/null 2>&1; then
                echo -e "${green}New WebBasePath: ${config_webBasePath}${plain}"
                echo -e "${green}Access URL: http://${server_ip}:${existing_port}/${config_webBasePath}${plain}"
            else
                echo -e "${red}Error: Failed to set WebBasePath${plain}"
                return 1
            fi
        fi
    else
        if [[ "$existing_hasDefaultCredential" == "true" ]]; then
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)

            echo -e "${yellow}Default credentials detected. Security update required...${plain}"
            if /usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}" >/dev/null 2>&1; then
                echo -e "Generated new random login credentials:"
                echo -e "###############################################"
                echo -e "${green}Username: ${config_username}${plain}"
                echo -e "${green}Password: ${config_password}${plain}"
                echo -e "###############################################"
            else
                echo -e "${red}Error: Failed to update credentials${plain}"
                return 1
            fi
        else
            echo -e "${green}Username, Password, and WebBasePath are properly set. Exiting...${plain}"
        fi
    fi

    # Run migration
    if /usr/local/x-ui/x-ui migrate >/dev/null 2>&1; then
        echo -e "${green}Migration completed successfully${plain}"
    else
        echo -e "${yellow}Warning: Migration may have failed, but continuing...${plain}"
    fi
}

install_x-ui() {
    cd /usr/local/

    if [ $# == 0 ]; then
        tag_version=$(curl -Ls "https://api.github.com/repos/azavaxhuman/4x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$tag_version" ]]; then
            echo -e "${red}Failed to fetch x-ui version, it may be due to GitHub API restrictions, please try it later${plain}"
            exit 1
        fi
        echo -e "Got x-ui latest version: ${tag_version}, beginning the installation..."
        wget -N -O /usr/local/x-ui-linux-$(arch).tar.gz https://github.com/azavaxhuman/4x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Downloading x-ui failed, please be sure that your server can access GitHub ${plain}"
            exit 1
        fi
    else
        tag_version=$1
        tag_version_numeric=${tag_version#v}
        min_version="2.3.5"

        if [[ "$(printf '%s\n' "$min_version" "$tag_version_numeric" | sort -V | head -n1)" != "$min_version" ]]; then
            echo -e "${red}Please use a newer version (at least v2.3.5). Exiting installation.${plain}"
            exit 1
        fi

        url="https://github.com/azavaxhuman/4x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz"
        echo -e "Beginning to install x-ui $1"
        wget -N -O /usr/local/x-ui-linux-$(arch).tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Download x-ui $1 failed, please check if the version exists ${plain}"
            exit 1
        fi
    fi

    if [[ -e /usr/local/x-ui/ ]]; then
        systemctl stop x-ui
        rm /usr/local/x-ui/ -rf
    fi

    tar zxvf x-ui-linux-$(arch).tar.gz
    rm x-ui-linux-$(arch).tar.gz -f
    
    # The extracted directory is named x-ui-<arch>, not x-ui
    EXTRACTED_DIR="x-ui-$(arch)"
    if [ ! -d "$EXTRACTED_DIR" ]; then
        echo -e "${red}Error: Expected directory $EXTRACTED_DIR not found after extraction${plain}"
        exit 1
    fi
    
    # Rename the extracted directory to x-ui
    mv "$EXTRACTED_DIR" x-ui
    cd x-ui
    
    # Debug: List contents of the directory
    echo -e "${blue}Contents of extracted directory:${plain}"
    ls -la
    
    chmod +x x-ui

    # Check the system's architecture and rename the file accordingly
    if [[ $(arch) == "armv5" || $(arch) == "armv6" || $(arch) == "armv7" ]]; then
        mv bin/xray-linux-$(arch) bin/xray-linux-arm
        chmod +x bin/xray-linux-arm
    fi

    chmod +x x-ui bin/xray-linux-$(arch)
    
    # Copy service file if it exists
    if [ -f "x-ui.service" ]; then
        cp -f x-ui.service /etc/systemd/system/
        echo -e "${green}Service file copied successfully${plain}"
    else
        echo -e "${red}Error: x-ui.service not found in extracted directory${plain}"
        return 1
    fi
    
    wget -O /usr/bin/x-ui https://raw.githubusercontent.com/azavaxhuman/4x-ui/main/x-ui.sh
    chmod +x /usr/bin/x-ui
    
    # Make sure x-ui.sh exists and is executable
    if [ -f "x-ui.sh" ]; then
        chmod +x x-ui.sh
    else
        echo -e "${yellow}Warning: x-ui.sh not found in extracted directory${plain}"
    fi
    config_after_install

    # Reload systemd and start the service
    systemctl daemon-reload
    if systemctl enable x-ui; then
        echo -e "${green}Service enabled successfully${plain}"
    else
        echo -e "${red}Failed to enable x-ui service${plain}"
        return 1
    fi
    
    if systemctl start x-ui; then
        echo -e "${green}Service started successfully${plain}"
    else
        echo -e "${red}Failed to start x-ui service${plain}"
        echo -e "${yellow}You can try starting it manually with: systemctl start x-ui${plain}"
        return 1
    fi
    echo -e "${green}x-ui ${tag_version}${plain} installation finished, it is running now..."
    echo -e ""
    echo -e "┌───────────────────────────────────────────────────────┐
│  ${blue}x-ui control menu usages (subcommands):${plain}              │
│                                                       │
│  ${blue}x-ui${plain}              - Admin Management Script          │
│  ${blue}x-ui start${plain}        - Start                            │
│  ${blue}x-ui stop${plain}         - Stop                             │
│  ${blue}x-ui restart${plain}      - Restart                          │
│  ${blue}x-ui status${plain}       - Current Status                   │
│  ${blue}x-ui settings${plain}     - Current Settings                 │
│  ${blue}x-ui enable${plain}       - Enable Autostart on OS Startup   │
│  ${blue}x-ui disable${plain}      - Disable Autostart on OS Startup  │
│  ${blue}x-ui log${plain}          - Check logs                       │
│  ${blue}x-ui banlog${plain}       - Check Fail2ban ban logs          │
│  ${blue}x-ui update${plain}       - Update                           │
│  ${blue}x-ui legacy${plain}       - legacy version                   │
│  ${blue}x-ui install${plain}      - Install                          │
│  ${blue}x-ui uninstall${plain}    - Uninstall                        │
└───────────────────────────────────────────────────────┘"
}

echo -e "${green}Running...${plain}"
install_base
install_x-ui $1
