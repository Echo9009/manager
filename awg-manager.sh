#!/bin/bash

# AmneziaWG Manager
# Author: Improved by Claude
# Version: 2.0

# Exit on error
set -e

# Configuration
APP=$(basename "$0")
LOCKFILE="/tmp/$APP.lock"
LOG_FILE="/var/log/amnezia-manager.log"
HOME_DIR="/etc/amnezia/amneziawg"
SERVER_NAME="awg0"
SERVER_IP_PREFIX="10.20.30"
SERVER_PORT=39547
DEFAULT_DNS="1.1.1.1, 8.8.8.8"

# Initialize log file
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
touch "$LOG_FILE" 2>/dev/null || true

# Create a safe lock file mechanism
trap "rm -f ${LOCKFILE}; exit" INT TERM EXIT
if ! ln -s "$APP" $LOCKFILE 2>/dev/null; then
    echo "ERROR: Another instance of $APP is already running" >&2
    exit 15
fi

# Set restrictive file permissions
umask 0077

# Logging functions
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
}

log_info() {
    log "INFO" "$1"
}

log_success() {
    log "SUCCESS" "$1"
}

log_warning() {
    log "WARNING" "$1"
}

log_error() {
    log "ERROR" "$1"
    echo "ERROR: $1" >&2
}

# Usage instructions
usage() {
  echo "Usage: $0 [<options>] [command [arg]]"
  echo "Options:"
  echo " -i : Init (Create server keys and configs)"
  echo " -c : Create new user"
  echo " -d : Delete user"
  echo " -L : Lock user"
  echo " -U : Unlock user"
  echo " -p : Print user config"
  echo " -q : Print user QR code"
  echo " -u <user> : User identifier (uniq field for vpn account)"
  echo " -s <server> : Server host for user connection"
  echo " -I <interface> : Network interface (default: auto-detect)"
  echo " -D <dns> : DNS servers (default: $DEFAULT_DNS)"
  echo " -P <port> : Server port (default: $SERVER_PORT)"
  echo " -h : Usage"
  exit 1
}

# Command execution with better error handling
execute_cmd() {
    local cmd="$1"
    local error_msg="${2:-Command failed}"
    local ignore_error="${3:-false}"
    
    log_info "Executing: $cmd"
    
    if ! eval "$cmd"; then
        if [ "$ignore_error" != "true" ]; then
            log_error "$error_msg"
            return 1
        else
            log_warning "$error_msg (ignored)"
            return 0
        fi
    fi
    return 0
}

# Reload server configuration
reload_server() {
    log_info "Reloading server configuration"
    execute_cmd "awg syncconf ${SERVER_NAME} <(awg-quick strip ${SERVER_NAME})" "Failed to reload server configuration"
    log_success "Server configuration reloaded"
}

# Find an available IP address
get_new_ip() {
    log_info "Finding available IP address"
    declare -A IP_EXISTS

    for IP in $(grep -i 'Address\s*=\s*' keys/*/*.conf 2>/dev/null | sed 's/\/[0-9]\+$//' | grep -Po '\d+$' || echo "")
    do
        IP_EXISTS["$IP"]=1
    done

    for IP in {2..254}
    do
        [ "${IP_EXISTS[$IP]}" ] || break
    done

    if [ "$IP" -eq 254 ]; then
        log_error "Can't determine new address - address space full"
        echo "ERROR: Can't determine new address - address space full" >&2
        exit 3
    fi

    log_success "Found available IP: ${SERVER_IP_PREFIX}.${IP}"
    echo "${SERVER_IP_PREFIX}.${IP}/32"
}

# Generate VPN configuration file for user
encode() {
    log_info "Generating VPN configuration for user ${USER}"
    if ! python3 encode.py "${USER}" > "keys/${USER}/${USER}.vpn"; then
        log_error "Failed to encode configuration for user ${USER}"
        return 1
    fi
    log_success "VPN configuration generated for user ${USER}"
    return 0
}

# Add user to server
add_user_to_server() {
    log_info "Adding user ${USER} to server configuration"
    
    if [ ! -f "keys/${USER}/public.key" ]; then
        log_error "User ${USER} does not exist"
        echo "ERROR: User ${USER} does not exist" >&2
        return 1
    fi

    local USER_PUB_KEY=$(cat "keys/${USER}/public.key")
    local USER_PSK_KEY=$(cat "keys/$USER/psk.key")
    local USER_IP=$(grep -i Address "keys/${USER}/${USER}.conf" | sed 's/Address\s*=\s*//i; s/\/.*//')

    if grep -q "# BEGIN ${USER}$" "$SERVER_NAME.conf"; then
        log_warning "User ${USER} already exists in server configuration"
        echo "User ${USER} already exists in server configuration"
        return 0
    fi

    # Create backup
    cp "$SERVER_NAME.conf" "$SERVER_NAME.conf.bak"

    # Add user
    cat <<EOF >> "$SERVER_NAME.conf"
# BEGIN ${USER}
[Peer]
PublicKey = ${USER_PUB_KEY}
AllowedIPs = ${USER_IP}
PresharedKey = ${USER_PSK_KEY}
# END ${USER}
EOF

    # Update routing
    execute_cmd "ip -4 route add ${USER_IP}/32 dev ${SERVER_NAME}" "Failed to add route for ${USER}" true

    log_success "User ${USER} added to server configuration"
    return 0
}

# Remove user from server
remove_user_from_server() {
    log_info "Removing user ${USER} from server configuration"
    
    # Create backup
    cp "$SERVER_NAME.conf" "$SERVER_NAME.conf.bak"
    
    # Remove user configuration
    sed -i "/# BEGIN ${USER}$/,/# END ${USER}$/d" "$SERVER_NAME.conf"
    
    if [ -f "keys/${USER}/${USER}.conf" ]; then
        local USER_IP=$(grep -i Address "keys/${USER}/${USER}.conf" | sed 's/Address\s*=\s*//i; s/\/.*//')
        execute_cmd "ip -4 route del ${USER_IP}/32 dev ${SERVER_NAME}" "Failed to delete route for ${USER}" true
    fi
    
    log_success "User ${USER} removed from server configuration"
    return 0
}

# Initialize the server
init() {
    log_info "Initializing AmneziaWG server"
    
    if [ -z "$SERVER_ENDPOINT" ]; then
        log_error "Server host/IP required"
        echo "ERROR: Server host/IP required (use -s option)" >&2
        return 1
    fi

    # Auto-detect server interface if not specified
    if [ -z "$SERVER_INTERFACE" ]; then
        SERVER_INTERFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
        if [ -z "$SERVER_INTERFACE" ]; then
            log_error "Could not auto-detect server interface"
            echo "ERROR: Cannot determine server interface" >&2
            echo "DEBUG: 'ip route' output:" >&2
            ip route >&2
            return 1
        fi
    fi

    log_info "Using network interface: $SERVER_INTERFACE"
    echo "Interface: $SERVER_INTERFACE"

    # Create necessary directories
    execute_cmd "mkdir -p \"keys/${SERVER_NAME}\"" "Failed to create server key directory"
    execute_cmd "echo -n \"$SERVER_ENDPOINT\" > \"keys/.server\"" "Failed to save server endpoint"

    # Generate server keys if not exist
    if [ ! -f "keys/${SERVER_NAME}/private.key" ]; then
        log_info "Generating server keys"
        execute_cmd "awg genkey | tee \"keys/${SERVER_NAME}/private.key\" | awg pubkey > \"keys/${SERVER_NAME}/public.key\"" "Failed to generate server keys"
    fi

    # Check if server is already initialized
    if [ -f "$SERVER_NAME.conf" ]; then
        log_warning "Server already initialized"
        echo "Server already initialized"
        return 0
    fi

    # Read server private key
    SERVER_PVT_KEY=$(cat "keys/$SERVER_NAME/private.key")

    # Create server configuration
    log_info "Creating server configuration"
    cat <<EOF > "$SERVER_NAME.conf"
[Interface]
Address = ${SERVER_IP_PREFIX}.1/32
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PVT_KEY}
PostUp = iptables -t nat -A POSTROUTING -o ${SERVER_INTERFACE} -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o ${SERVER_INTERFACE} -j MASQUERADE
Jc = 5
Jmin = 50
Jmax = 1000
S1 = 147
S2 = 57
H1 = 1121994835
H2 = 1702292146
H3 = 1975368295
H4 = 1948088518

EOF

    # Enable IP forwarding
    log_info "Enabling IP forwarding"
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        execute_cmd "echo net.ipv4.ip_forward=1 >> /etc/sysctl.conf" "Failed to configure IP forwarding"
    fi
    execute_cmd "sysctl -p" "Failed to apply sysctl settings" true

    # Enable and start the service
    log_info "Enabling and starting AmneziaWG service"
    execute_cmd "systemctl enable awg-quick@${SERVER_NAME}" "Failed to enable AmneziaWG service" true
    execute_cmd "awg-quick up ${SERVER_NAME}" "Failed to start AmneziaWG service" true

    log_success "Server initialized successfully"
    echo "Server initialized successfully"
    return 0
}

# Create new user
create_user() {
    log_info "Creating new user: ${USER}"
    
    if [ -f "keys/${USER}/${USER}.conf" ]; then
        log_warning "User ${USER} already exists"
        echo "WARNING: User ${USER} already exists" >&2
        return 0
    fi

    # Get server endpoint
    SERVER_ENDPOINT=$(cat "keys/.server")
    if [ -z "$SERVER_ENDPOINT" ]; then
        log_error "Server endpoint not found, run init first"
        echo "ERROR: Server endpoint not found. Run init first (-i option)" >&2
        return 1
    }
    
    # Get new IP address for user
    USER_IP=$(get_new_ip)
    
    # Create user directory
    execute_cmd "mkdir -p \"keys/${USER}\"" "Failed to create user directory"
    
    # Generate keys
    log_info "Generating keys for user ${USER}"
    execute_cmd "awg genkey | tee \"keys/${USER}/private.key\" | awg pubkey > \"keys/${USER}/public.key\" && awg genpsk > \"keys/${USER}/psk.key\"" "Failed to generate keys for user ${USER}"
    
    # Read keys
    USER_PVT_KEY=$(cat "keys/${USER}/private.key")
    USER_PUB_KEY=$(cat "keys/${USER}/public.key")
    USER_PSK_KEY=$(cat "keys/${USER}/psk.key")
    SERVER_PUB_KEY=$(cat "keys/$SERVER_NAME/public.key")
    
    # Create user configuration
    log_info "Creating configuration for user ${USER}"
    cat <<EOF > "keys/${USER}/${USER}.conf"
[Interface]
PrivateKey = ${USER_PVT_KEY}
Address = ${USER_IP}
DNS = ${DNS_SERVERS}
Jc = 5
Jmin = 50
Jmax = 1000
S1 = 147
S2 = 57
H1 = 1121994835
H2 = 1702292146
H3 = 1975368295
H4 = 1948088518

[Peer]
PublicKey = ${SERVER_PUB_KEY}
Endpoint = ${SERVER_ENDPOINT}:${SERVER_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 20
PresharedKey = ${USER_PSK_KEY}
EOF
    
    # Generate encoded configuration
    encode
    
    # Add user to server
    add_user_to_server
    
    # Reload server
    reload_server
    
    log_success "User ${USER} created successfully"
    return 0
}

# Parse command line arguments
unset USER
unset INIT
unset CREATE
unset DELETE
unset LOCK
unset UNLOCK
unset PRINT_USER_CONFIG
unset PRINT_QR_CODE
DNS_SERVERS="$DEFAULT_DNS"

# Auto-detect server interface if not specified
SERVER_INTERFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)

while getopts ":icdpqhLUu:I:s:D:P:" opt; do
  case $opt in
     i) INIT=1 ;;
     c) CREATE=1 ;;
     d) DELETE=1 ;;
     L) LOCK=1 ;;
     U) UNLOCK=1 ;;
     p) PRINT_USER_CONFIG=1 ;;
     q) PRINT_QR_CODE=1 ;;
     u) USER="$OPTARG" ;;
     I) SERVER_INTERFACE="$OPTARG" ;;
     s) SERVER_ENDPOINT="$OPTARG" ;;
     D) DNS_SERVERS="$OPTARG" ;;
     P) SERVER_PORT="$OPTARG" ;;
     h) usage ;;
    \?) echo "Invalid option: -$OPTARG" ; exit 1 ;;
     :) echo "Option -$OPTARG requires an argument" ; exit 1 ;;
  esac
done

# Check if at least one option was provided
[ $# -lt 1 ] && usage

# Ensure we're in the right directory
cd "$HOME_DIR" || {
    log_error "Cannot change to $HOME_DIR directory"
    echo "ERROR: Cannot change to $HOME_DIR directory" >&2
    exit 1
}

# Execute commands
if [ $INIT ]; then
    init
    exit $?
fi

# Check if server is initialized
if [ ! -f "keys/$SERVER_NAME/public.key" ]; then
    log_error "Server not initialized"
    echo "ERROR: Run init script before (-i option)" >&2
    exit 2
fi

# Check if user is specified for user-related commands
if [ -z "${USER}" ] && [[ $CREATE || $DELETE || $LOCK || $UNLOCK || $PRINT_USER_CONFIG || $PRINT_QR_CODE ]]; then
    log_error "User required"
    echo "ERROR: User required (-u option)" >&2
    exit 1
fi

# Execute appropriate command
if [ $CREATE ]; then
    create_user
fi

if [ $DELETE ]; then
    remove_user_from_server
    reload_server
    execute_cmd "rm -rf \"keys/${USER}\"" "Failed to delete user directory" true
    log_success "User ${USER} deleted"
    exit 0
fi

if [ $LOCK ]; then
    remove_user_from_server
    reload_server
    log_success "User ${USER} locked"
    exit 0
fi

if [ $UNLOCK ]; then
    add_user_to_server
    reload_server
    log_success "User ${USER} unlocked"
    exit 0
fi

if [ $PRINT_USER_CONFIG ]; then
    if [ ! -f "keys/${USER}/${USER}.conf" ]; then
        log_error "User ${USER} configuration not found"
        echo "ERROR: User ${USER} configuration not found" >&2
        exit 1
    fi
    cat "keys/${USER}/${USER}.conf"
elif [ $PRINT_QR_CODE ]; then
    if [ ! -f "keys/${USER}/${USER}.vpn" ]; then
        log_error "User ${USER} VPN configuration not found"
        echo "ERROR: User ${USER} VPN configuration not found" >&2
        exit 1
    fi
    qrencode -t ansiutf8 < "keys/${USER}/${USER}.vpn"
fi

exit 0
