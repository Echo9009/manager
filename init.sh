#!/bin/bash

# AmneziaWG Server Installation Script
# Author: Improved by Claude
# Version: 2.0

# Exit on error, undefined variable, or pipe failures
set -euo pipefail

# Configuration
LOG_FILE="/var/log/amnezia-install.log"
INSTALL_DIR="/etc/amnezia/amneziawg"
GO_VERSION="1.22.2"
GO_INSTALL_DIR="/opt/go"

# Initialize log file
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

# Logging functions
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$1"
    colorized_echo "blue" "$1"
}

log_success() {
    log "SUCCESS" "$1"
    colorized_echo "green" "$1"
}

log_warning() {
    log "WARNING" "$1"
    colorized_echo "yellow" "$1"
}

log_error() {
    log "ERROR" "$1"
    colorized_echo "red" "$1"
    if [ -n "${2:-}" ]; then
        exit "$2"
    fi
}

colorized_echo() {
    local color=$1
    local text=$2
    
    case $color in
        "red")     printf "\e[91m%s\e[0m\n" "$text" ;;
        "green")   printf "\e[92m%s\e[0m\n" "$text" ;;
        "yellow")  printf "\e[93m%s\e[0m\n" "$text" ;;
        "blue")    printf "\e[94m%s\e[0m\n" "$text" ;;
        "magenta") printf "\e[95m%s\e[0m\n" "$text" ;;
        "cyan")    printf "\e[96m%s\e[0m\n" "$text" ;;
        *)         echo "$text" ;;
    esac
}

# Command execution with error handling
execute_cmd() {
    local cmd="$1"
    local error_msg="${2:-Command failed}"
    local exit_code="${3:-1}"
    
    log_info "Executing: $cmd"
    
    if ! eval "$cmd"; then
        log_error "$error_msg" "$exit_code"
    fi
}

# Check if script is run as root
check_running_as_root() {
    log_info "Checking root privileges"
    if [ "$(id -u)" != "0" ]; then
        log_error "This script must be run as root" 1
    fi
}

# Detect OS
detect_os() {
    log_info "Detecting operating system"
    
    if [ -f /etc/lsb-release ]; then
        OS=$(lsb_release -si)
    elif [ -f /etc/os-release ]; then
        OS=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"')
    elif [ -f /etc/redhat-release ]; then
        OS=$(cat /etc/redhat-release | awk '{print $1}')
    elif [ -f /etc/arch-release ]; then
        OS="Arch"
    else
        log_error "Unsupported operating system" 1
    fi
    
    log_info "Detected OS: $OS"
    
    # Validate supported OS
    if [[ ! "$OS" =~ ^(Ubuntu|Debian) ]]; then
        log_error "Unsupported operating system: $OS. This script only supports Ubuntu and Debian." 1
    fi
}

# Update package manager
update_package_manager() {
    log_info "Updating package manager"
    
    if [[ "$OS" =~ ^(Ubuntu|Debian) ]]; then
        PKG_MANAGER="apt-get"
        execute_cmd "$PKG_MANAGER update" "Failed to update package repository"
    else
        log_error "Unsupported operating system: $OS" 1
    fi
}

# Install required packages
install_packages() {
    log_info "Installing required packages"
    
    # Create a package list with versions for better reproducibility
    PACKAGES=(
        "build-essential"
        "curl"
        "make"
        "git"
        "wget"
        "qrencode"
        "python3"
        "python3-pip"
        "iptables"
        "net-tools"
    )
    
    if [[ "$OS" =~ ^(Ubuntu|Debian) ]]; then
        packages_str=$(IFS=" " ; echo "${PACKAGES[*]}")
        execute_cmd "$PKG_MANAGER install -y $packages_str" "Failed to install required packages"
    else
        log_error "Unsupported operating system: $OS" 1
    fi
    
    log_success "Required packages installed successfully"
}

# Install Go
install_go() {
    log_info "Checking Go installation"
    
    if command -v go &> /dev/null; then
        current_version=$(go version | awk '{print $3}' | sed 's/go//')
        log_success "Go is already installed (version $current_version)"
        return
    fi
    
    log_info "Installing Go version $GO_VERSION"
    
    # Create installation directory
    execute_cmd "mkdir -p $GO_INSTALL_DIR"
    execute_cmd "cd $GO_INSTALL_DIR"
    
    # Download and install Go
    go_archive="go${GO_VERSION}.linux-amd64.tar.gz"
    go_url="https://go.dev/dl/${go_archive}"
    
    execute_cmd "wget -q --show-progress $go_url" "Failed to download Go"
    execute_cmd "rm -rf /usr/local/go && tar -C /usr/local -xzf ${go_archive}" "Failed to extract Go"
    
    # Set up environment variables
    if ! grep -q "/usr/local/go/bin" /etc/profile; then
        execute_cmd "echo 'export PATH=\$PATH:/usr/local/go/bin' >> /etc/profile"
    fi
    
    # Apply changes to current session
    export PATH=$PATH:/usr/local/go/bin
    source /etc/profile &> /dev/null || true
    
    # Verify Go installation
    if command -v go &> /dev/null; then
        installed_version=$(go version | awk '{print $3}' | sed 's/go//')
        log_success "Go installed successfully (version $installed_version)"
    else
        log_error "Go installation failed. Please check the logs at $LOG_FILE" 1
    fi
}

# Install AmneziaWG Go
install_amneziawg_go() {
    log_info "Checking AmneziaWG Go installation"
    
    if command -v amneziawg-go &> /dev/null; then
        log_success "AmneziaWG Go is already installed"
        return
    fi
    
    log_info "Installing AmneziaWG Go"
    
    # Clone repository
    execute_cmd "rm -rf /opt/amnezia-go && mkdir -p /opt/amnezia-go"
    execute_cmd "git clone --depth=1 https://github.com/amnezia-vpn/amneziawg-go.git /opt/amnezia-go"
    execute_cmd "cd /opt/amnezia-go"
    
    # Build and install
    execute_cmd "make" "Failed to build AmneziaWG Go"
    execute_cmd "cp /opt/amnezia-go/amneziawg-go /usr/bin/amneziawg-go"
    execute_cmd "chmod 755 /usr/bin/amneziawg-go"
    
    # Verify installation
    if command -v amneziawg-go &> /dev/null; then
        log_success "AmneziaWG Go installed successfully"
    else
        log_error "AmneziaWG Go installation failed" 1
    fi
}

# Install AmneziaWG Tools
install_amneziawg_tools() {
    log_info "Checking AmneziaWG Tools installation"
    
    if command -v awg &> /dev/null; then
        log_success "AmneziaWG Tools already installed"
        return
    fi
    
    log_info "Installing AmneziaWG Tools"
    
    # Clone repository
    execute_cmd "rm -rf /opt/amnezia-tools && mkdir -p /opt/amnezia-tools"
    execute_cmd "git clone --depth=1 https://github.com/amnezia-vpn/amneziawg-tools.git /opt/amnezia-tools"
    execute_cmd "cd /opt/amnezia-tools/src"
    
    # Build and install
    execute_cmd "make && make install" "Failed to build and install AmneziaWG Tools"
    
    # Verify installation
    if command -v awg &> /dev/null; then
        log_success "AmneziaWG Tools installed successfully"
    else
        log_error "AmneziaWG Tools installation failed" 1
    fi
}

# Install AWG Manager
install_awg_manager() {
    log_info "Checking AWG Manager installation"
    
    # Create installation directory
    execute_cmd "mkdir -p $INSTALL_DIR"
    
    if [ -f "$INSTALL_DIR/awg-manager.sh" ]; then
        log_info "AWG Manager is already installed, checking for updates"
        
        # Compare current file with remote version to check for updates
        tempfile=$(mktemp)
        execute_cmd "wget -q -O $tempfile https://raw.githubusercontent.com/Echo9009/manager/master/awg-manager.sh"
        
        if ! diff -q "$INSTALL_DIR/awg-manager.sh" "$tempfile" &>/dev/null; then
            log_info "New version of AWG Manager found, updating"
            execute_cmd "cp $tempfile $INSTALL_DIR/awg-manager.sh"
            execute_cmd "chmod 700 $INSTALL_DIR/awg-manager.sh"
            log_success "AWG Manager updated successfully"
        else
            log_success "AWG Manager is up to date"
        fi
        rm -f "$tempfile"
    else
        log_info "Downloading AWG Manager"
        execute_cmd "wget -q -O $INSTALL_DIR/awg-manager.sh https://raw.githubusercontent.com/Echo9009/manager/master/awg-manager.sh"
        execute_cmd "chmod 700 $INSTALL_DIR/awg-manager.sh"
        
        if [ -f "$INSTALL_DIR/awg-manager.sh" ]; then
            log_success "AWG Manager downloaded successfully"
        else
            log_error "AWG Manager download failed" 1
        fi
    fi
}

# Install encode.py
install_encode_file() {
    log_info "Checking encode.py installation"
    
    if [ -f "$INSTALL_DIR/encode.py" ]; then
        log_info "encode.py is already installed, checking for updates"
        
        # Compare current file with remote version
        tempfile=$(mktemp)
        execute_cmd "wget -q -O $tempfile https://raw.githubusercontent.com/Echo9009/manager/master/encode.py"
        
        if ! diff -q "$INSTALL_DIR/encode.py" "$tempfile" &>/dev/null; then
            log_info "New version of encode.py found, updating"
            execute_cmd "cp $tempfile $INSTALL_DIR/encode.py"
            log_success "encode.py updated successfully"
        else
            log_success "encode.py is up to date"
        fi
        rm -f "$tempfile"
    else
        log_info "Downloading encode.py"
        execute_cmd "wget -q -O $INSTALL_DIR/encode.py https://raw.githubusercontent.com/Echo9009/manager/master/encode.py"
        
        if [ -f "$INSTALL_DIR/encode.py" ]; then
            log_success "encode.py downloaded successfully"
        else
            log_error "encode.py download failed" 1
        fi
    fi
    
    # Install dependencies
    log_info "Installing Python dependencies"
    execute_cmd "pip3 install -q PyQt6" "Failed to install PyQt6"
    log_success "Python dependencies installed successfully"
}

# Configure system settings
configure_system() {
    log_info "Configuring system settings"
    
    # Enable IP forwarding
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        execute_cmd "echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf"
        execute_cmd "sysctl -p" "Failed to apply sysctl settings"
    fi
    
    log_success "System settings configured successfully"
}

# Main installation process
install_all() {
    log_info "Starting AmneziaWG server installation"
    
    # Print banner
    echo -e "\n======================================================"
    echo -e "    AmneziaWG Server Installation - Version 2.0"
    echo -e "======================================================"
    echo -e "Installation log: $LOG_FILE\n"
    
    # Run installation steps
    check_running_as_root
    detect_os
    update_package_manager
    install_packages
    install_go
    install_amneziawg_go
    install_amneziawg_tools
    install_awg_manager
    install_encode_file
    configure_system
    
    # Display completion message
    echo -e "\n======================================================"
    echo -e "    AmneziaWG Server Installation Complete!"
    echo -e "======================================================"
    echo -e "Installation directory: $INSTALL_DIR"
    echo -e "Manager script: $INSTALL_DIR/awg-manager.sh"
    echo -e ""
    echo -e "To initialize the server: $INSTALL_DIR/awg-manager.sh -i -s YOUR_SERVER_IP"
    echo -e "To create a new user: $INSTALL_DIR/awg-manager.sh -u USERNAME -c"
    echo -e "======================================================"
    
    log_success "Installation completed successfully"
}

# Script usage
usage() {
    echo "Usage: $0 install"
    echo "  install    - Install or update AmneziaWG server"
    exit 1
}

# Main entry point
case "${1:-}" in
    install)
        install_all
        ;;
    *)
        usage
        ;;
esac

