#!/bin/bash
# ============================================================
# Multi-server SSH Key & Connection Management Script V-3.3
# Supports multiple OS (Debian/Ubuntu, RHEL/CentOS, etc.)
# Juli 2026 by sigit afandhi - apjii
# Versi dioptimalkan: caching, paralelisasi, perbaikan performa,
# penanganan sudo otomatis berdasarkan deteksi user root.
# ============================================================

# Configuration
SERVER_LIST="listserver.txt"
SSH_DIR="$HOME/.ssh"
KNOWN_HOSTS="$SSH_DIR/known_hosts"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Global cache
SERVERS_CACHED=()
SERVERS_LOADED=false
SELECTED_INDICES=()

# ----------------------------------------------------------------------
# Helper Functions
# ----------------------------------------------------------------------

info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

detect_package_manager() {
    if command_exists apt-get; then echo "apt-get"
    elif command_exists yum; then echo "yum"
    elif command_exists dnf; then echo "dnf"
    elif command_exists zypper; then echo "zypper"
    else echo "unknown"; fi
}

install_package_local() {
    local pkg="$1"
    if ! command_exists "$pkg"; then
        local pkg_name=""
        case "$pkg" in
            dig|nslookup) pkg_name="dnsutils" ;;
            traceroute) pkg_name="traceroute" ;;
            netstat) pkg_name="net-tools" ;;
            whois) pkg_name="whois" ;;
            *) pkg_name="$pkg" ;;
        esac
        warn "Command '$pkg' not found. Package to install: $pkg_name"
        read -p "Do you want to install it now? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            local pkg_manager=$(detect_package_manager)
            case $pkg_manager in
                apt-get) sudo apt-get update && sudo apt-get install -y "$pkg_name" ;;
                yum) sudo yum install -y "$pkg_name" ;;
                dnf) sudo dnf install -y "$pkg_name" ;;
                zypper) sudo zypper install -y "$pkg_name" ;;
                *) error "Unsupported package manager. Install '$pkg_name' manually."; return 1 ;;
            esac
            if command_exists "$pkg"; then info "Installed '$pkg'."; return 0
            else error "Installation failed for '$pkg'."; return 1; fi
        else warn "Skipping installation."; return 1; fi
    fi
    return 0
}

install_package_if_missing() {
    local pkg="$1"
    if ! command_exists "$pkg"; then
        warn "Command '$pkg' not found."
        read -p "Do you want to install it now? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            local pkg_manager=$(detect_package_manager)
            case $pkg_manager in
                apt-get) sudo apt-get update && sudo apt-get install -y "$pkg" ;;
                yum) sudo yum install -y "$pkg" ;;
                dnf) sudo dnf install -y "$pkg" ;;
                zypper) sudo zypper install -y "$pkg" ;;
                *) error "Unsupported package manager. Install '$pkg' manually."; return 1 ;;
            esac
            if command_exists "$pkg"; then info "Installed '$pkg'."; return 0
            else error "Installation failed for '$pkg'."; return 1; fi
        else warn "Skipping installation."; return 1; fi
    fi
    return 0
}

ensure_base_packages() {
    local missing=0
    install_package_if_missing "ssh" || ((missing++))
    install_package_if_missing "ssh-keygen" || ((missing++))
    install_package_if_missing "ssh-copy-id" || ((missing++))
    return $missing
}

confirm_action() {
    local msg="$1"
    echo -n "$msg (y/N): "
    read -r ans
    case "$ans" in
        y|Y) return 0 ;;
        *) return 1 ;;
    esac
}

run_script_on_server() {
    local server_str="$1"
    local script="$2"
    local user host port
    read user host port <<< $(parse_server_string "$server_str")
    local ssh_args=(-p "$port")
    [[ -n "$user" ]] && ssh_args+=("$user@$host") || ssh_args+=("$host")
    # Kirim skrip dengan deteksi sudo di dalamnya
    ssh "${ssh_args[@]}" "bash -s" <<< "$script"
}

# ----------------------------------------------------------------------
# Server String Parsing & SSH Wrappers (optimized)
# ----------------------------------------------------------------------

parse_server_string() {
    local server_str="$1"
    local user host port host_port
    if [[ "$server_str" == *"@"* ]]; then
        user="${server_str%%@*}"
        host_port="${server_str#*@}"
    else
        user=""
        host_port="$server_str"
    fi
    if [[ "$host_port" == *":"* ]]; then
        host="${host_port%:*}"
        port="${host_port#*:}"
    else
        host="$host_port"
        port="22"
    fi
    echo "$user" "$host" "$port"
}

ssh_to_server() {
    local server_str="$1"
    local cmd="$2"
    shift 2
    local user host port
    read user host port <<< $(parse_server_string "$server_str")
    local ssh_args=(-p "$port")
    [[ -n "$user" ]] && ssh_args+=("$user@$host") || ssh_args+=("$host")
    if [[ -z "$cmd" ]]; then
        ssh "${ssh_args[@]}" "$@"
    else
        ssh "${ssh_args[@]}" "$cmd" "$@"
    fi
}

run_remote_script() {
    local server_str="$1"
    local script="$2"
    local user host port
    read user host port <<< $(parse_server_string "$server_str")
    local ssh_args=(-p "$port")
    [[ -n "$user" ]] && ssh_args+=("$user@$host") || ssh_args+=("$host")
    ssh "${ssh_args[@]}" "bash -s" <<< "$script"
}

run_remote_script_sudo() {
    local server_str="$1"
    local script="$2"
    # Kita tidak membungkus dengan sudo di luar, tetapi kita tambahkan deteksi di dalam skrip
    # Jadi kita panggil run_remote_script biasa, tapi skrip sudah mengandung logika sudo
    run_remote_script "$server_str" "$script"
}

ssh_copy_id_to_server() {
    local server_str="$1"
    local user host port
    read user host port <<< $(parse_server_string "$server_str")
    local copy_args=(-p "$port")
    [[ -n "$user" ]] && copy_args+=("$user@$host") || copy_args+=("$host")
    ssh-copy-id "${copy_args[@]}"
}

get_host_from_server() {
    local server_str="$1"
    local user host port
    read user host port <<< $(parse_server_string "$server_str")
    echo "$host"
}

# ----------------------------------------------------------------------
# Server List Management (with caching)
# ----------------------------------------------------------------------

read_servers() {
    if [[ "$SERVERS_LOADED" == "true" ]]; then
        return 0
    fi
    if [[ ! -f "$SERVER_LIST" ]]; then
        touch "$SERVER_LIST"
        info "Created empty server list: $SERVER_LIST"
    fi
    mapfile -t SERVERS_CACHED < <(grep -v '^[[:space:]]*$' "$SERVER_LIST" | grep -v '^[[:space:]]*#' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    SERVERS_LOADED=true
}

refresh_servers() {
    SERVERS_LOADED=false
    read_servers
}

display_servers() {
    if [[ ${#SERVERS_CACHED[@]} -eq 0 ]]; then
        echo "No servers in list."
        return 1
    fi
    echo "Available servers:"
    for i in "${!SERVERS_CACHED[@]}"; do
        echo "  $((i+1))) ${SERVERS_CACHED[$i]}"
    done
    return 0
}

select_servers() {
    SELECTED_INDICES=()
    if [[ ${#SERVERS_CACHED[@]} -eq 0 ]]; then
        warn "No servers available."
        return 1
    fi
    display_servers
    echo "Enter server numbers (e.g., 1,2,3 or 1-3 or 'all'): "
    read -r selection
    selection=$(echo "$selection" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ -z "$selection" ]]; then
        warn "No input provided."
        return 1
    fi
    if [[ "$selection" == "all" ]]; then
        for i in "${!SERVERS_CACHED[@]}"; do
            SELECTED_INDICES+=("$((i+1))")
        done
    else
        IFS=',' read -ra parts <<< "$selection"
        for part in "${parts[@]}"; do
            part=$(echo "$part" | tr -d '[:space:]')
            if [[ "$part" =~ ^[0-9]+$ ]]; then
                SELECTED_INDICES+=("$part")
            elif [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                start="${BASH_REMATCH[1]}"
                end="${BASH_REMATCH[2]}"
                if (( start <= end )); then
                    for ((i=start; i<=end; i++)); do
                        SELECTED_INDICES+=("$i")
                    done
                else
                    warn "Invalid range: $part (start > end)"
                fi
            else
                warn "Invalid selection: $part"
            fi
        done
    fi
    if [[ ${#SELECTED_INDICES[@]} -eq 0 ]]; then
        warn "No servers selected."
        return 1
    fi
    local sorted_unique=()
    while IFS= read -r num; do
        sorted_unique+=("$num")
    done < <(printf '%s\n' "${SELECTED_INDICES[@]}" | sort -nu)
    SELECTED_INDICES=("${sorted_unique[@]}")
    local max=${#SERVERS_CACHED[@]}
    local valid=()
    for idx in "${SELECTED_INDICES[@]}"; do
        if (( idx >= 1 && idx <= max )); then
            valid+=("$idx")
        else
            warn "Index $idx out of range (1..$max)"
        fi
    done
    SELECTED_INDICES=("${valid[@]}")
    if [[ ${#SELECTED_INDICES[@]} -eq 0 ]]; then
        warn "No valid servers selected."
        return 1
    fi
    return 0
}

get_server_by_index() {
    local idx=$1
    if (( idx >= 1 && idx <= ${#SERVERS_CACHED[@]} )); then
        echo "${SERVERS_CACHED[$((idx-1))]}"
    else
        echo ""
    fi
}

# ----------------------------------------------------------------------
# Parallel execution helper (optional, set PARALLEL=true to enable)
# ----------------------------------------------------------------------

PARALLEL=${PARALLEL:-false}

run_action_on_servers() {
    local script="$1"
    local task_name="$2"
    read_servers
    if ! select_servers; then return; fi

    local pids=()
    if [[ "$PARALLEL" == "true" ]]; then
        for idx in "${SELECTED_INDICES[@]}"; do
            local server=$(get_server_by_index "$idx")
            (
                info "Running $task_name on $server ..."
                echo "----------------------------------------"
                run_remote_script "$server" "$script"
                echo "----------------------------------------"
            ) &
            pids+=($!)
        done
        wait "${pids[@]}"
    else
        for idx in "${SELECTED_INDICES[@]}"; do
            local server=$(get_server_by_index "$idx")
            info "Running $task_name on $server ..."
            echo "----------------------------------------"
            run_remote_script "$server" "$script"
            echo "----------------------------------------"
        done
    fi
}

run_action_on_servers_sudo() {
    local script="$1"
    local task_name="$2"
    read_servers
    if ! select_servers; then return; fi

    local pids=()
    if [[ "$PARALLEL" == "true" ]]; then
        for idx in "${SELECTED_INDICES[@]}"; do
            local server=$(get_server_by_index "$idx")
            (
                info "Running $task_name on $server (with sudo if needed) ..."
                echo "----------------------------------------"
                run_remote_script "$server" "$script"
                echo "----------------------------------------"
            ) &
            pids+=($!)
        done
        wait "${pids[@]}"
    else
        for idx in "${SELECTED_INDICES[@]}"; do
            local server=$(get_server_by_index "$idx")
            info "Running $task_name on $server (with sudo if needed) ..."
            echo "----------------------------------------"
            run_remote_script "$server" "$script"
            echo "----------------------------------------"
        done
    fi
}

run_info_command() {
    local cmd="$1"
    local desc="$2"
    read_servers
    if ! select_servers; then return; fi
    for idx in "${SELECTED_INDICES[@]}"; do
        local server=$(get_server_by_index "$idx")
        info "$desc on $server"
        echo "----------------------------------------"
        ssh_to_server "$server" "$cmd" 2>&1
        echo "----------------------------------------"
    done
}

run_info_command_sudo() {
    local cmd="$1"
    local desc="$2"
    read_servers
    if ! select_servers; then return; fi
    for idx in "${SELECTED_INDICES[@]}"; do
        local server=$(get_server_by_index "$idx")
        info "$desc on $server (may require sudo)"
        echo "----------------------------------------"
        # Kita jalankan dengan bash -c agar deteksi sudo terjadi
        ssh_to_server "$server" "bash -c 'if [ \$(id -u) -eq 0 ]; then SUDO=\"\"; else SUDO=\"sudo\"; fi; \$SUDO $cmd'" 2>&1
        echo "----------------------------------------"
    done
}

# ======================================================================
# 1. SSH Key Management
# ======================================================================

generate_ssh_key() {
    info "Generating SSH key pair locally..."
    if [[ -f "$SSH_DIR/id_rsa" ]]; then
        warn "Existing key found. Overwrite? (y/N): "
        read -r -n 1 ans
        echo
        if [[ ! $ans =~ ^[Yy]$ ]]; then
            info "Aborted."
            return
        fi
    fi
    ssh-keygen -t rsa -b 4096 -f "$SSH_DIR/id_rsa" -N ""
    if [[ $? -eq 0 ]]; then
        info "SSH key generated."
    else
        error "Key generation failed."
    fi
}

import_public_key() {
    ensure_base_packages || return 1
    if [[ ! -f "$SSH_DIR/id_rsa.pub" ]]; then
        error "Local public key not found. Generate one first (option 4 in SSH Key Management)."
        return 1
    fi
    read_servers
    if ! select_servers; then return; fi
    for idx in "${SELECTED_INDICES[@]}"; do
        local server=$(get_server_by_index "$idx")
        info "Copying public key to $server ..."
        ssh_copy_id_to_server "$server"
        if [[ $? -eq 0 ]]; then
            info "Key copied successfully to $server."
        else
            error "Failed to copy key to $server."
        fi
    done
}

test_passwordless() {
    ensure_base_packages || return 1
    read_servers
    if ! select_servers; then return; fi
    for idx in "${SELECTED_INDICES[@]}"; do
        local server=$(get_server_by_index "$idx")
        info "Testing passwordless SSH to $server ..."
        ssh_to_server "$server" "echo 'OK'" -o BatchMode=yes -o ConnectTimeout=5
        if [[ $? -eq 0 ]]; then
            info "Passwordless SSH to $server: SUCCESS"
        else
            warn "Passwordless SSH to $server: FAILED"
        fi
    done
}

repair_ssh_key() {
    info "Repairing local SSH configuration..."
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    [[ -f "$SSH_DIR/id_rsa" ]] && chmod 600 "$SSH_DIR/id_rsa"
    [[ -f "$SSH_DIR/id_rsa.pub" ]] && chmod 644 "$SSH_DIR/id_rsa.pub"
    [[ -f "$KNOWN_HOSTS" ]] && chmod 644 "$KNOWN_HOSTS"
    info "Local SSH permissions repaired."
    read_servers
    if select_servers; then
        for idx in "${SELECTED_INDICES[@]}"; do
            local server=$(get_server_by_index "$idx")
            local host=$(get_host_from_server "$server")
            if [[ -n "$host" ]]; then
                ssh-keygen -R "$host" 2>/dev/null
                info "Removed $host from known_hosts."
            fi
        done
    fi
}

remove_ssh_key() {
    read_servers
    if ! select_servers; then return; fi
    for idx in "${SELECTED_INDICES[@]}"; do
        local server=$(get_server_by_index "$idx")
        info "Removing local public key from $server ..."
        if [[ ! -f "$SSH_DIR/id_rsa.pub" ]]; then
            error "Local public key not found."
            continue
        fi
        local pubkey=$(cat "$SSH_DIR/id_rsa.pub")
        local escaped_pubkey=$(printf '%s\n' "$pubkey" | sed -e 's/[\/&]/\\&/g')
        ssh_to_server "$server" "sed -i '/$escaped_pubkey/d' ~/.ssh/authorized_keys" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            info "Key removed from $server."
        else
            warn "Failed to remove key from $server."
        fi
    done
}

regenerate_ssh_key() {
    if [[ -f "$SSH_DIR/id_rsa" ]]; then
        warn "Existing key found. Delete and generate new? (y/N): "
        read -r -n 1 ans
        echo
        if [[ ! $ans =~ ^[Yy]$ ]]; then
            info "Aborted."
            return
        fi
        rm -f "$SSH_DIR/id_rsa" "$SSH_DIR/id_rsa.pub"
    fi
    generate_ssh_key
    echo "Do you want to copy the new key to remote servers? (y/N): "
    read -r -n 1 ans
    echo
    if [[ $ans =~ ^[Yy]$ ]]; then
        import_public_key
    fi
}

# ======================================================================
# 2. SSH Management
# ======================================================================

add_new_server() {
    ensure_base_packages || return 1
    echo "Enter new server details (format: user@host[:port] or host[:port]): "
    read -r new_server
    new_server=$(echo "$new_server" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ -z "$new_server" ]]; then
        error "No input provided."
        return
    fi
    read_servers
    for s in "${SERVERS_CACHED[@]}"; do
        if [[ "$s" == "$new_server" ]]; then
            warn "Server '$new_server' already exists in list."
            return
        fi
    done
    if [[ -s "$SERVER_LIST" ]] && [[ "$(tail -c1 "$SERVER_LIST")" != "" ]]; then
        echo "" >> "$SERVER_LIST"
    fi
    echo "$new_server" >> "$SERVER_LIST"
    refresh_servers
    info "Added server: $new_server"
    if [[ -f "$SSH_DIR/id_rsa.pub" ]]; then
        echo "Do you want to copy your public key to this server now? (Y/n): "
        read -r -n 1 ans
        echo
        if [[ ! $ans =~ ^[Nn]$ ]]; then
            ssh_copy_id_to_server "$new_server"
            if [[ $? -eq 0 ]]; then
                info "Key copied to $new_server."
            else
                error "Failed to copy key."
            fi
        fi
    else
        warn "No local public key found. Generate one first (option 4 in SSH Key Management)."
    fi
}

remote_ssh_manual() {
    echo "Enter server (format: user@host[:port] or host[:port]): "
    read -r server_input
    server_input=$(echo "$server_input" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ -z "$server_input" ]]; then
        error "No input."
        return
    fi
    ssh_to_server "$server_input"
}

remote_ssh_from_list() {
    read_servers
    if ! select_servers; then return; fi
    for idx in "${SELECTED_INDICES[@]}"; do
        local server=$(get_server_by_index "$idx")
        info "Connecting to $server ..."
        ssh_to_server "$server"
        echo "--- Disconnected from $server ---"
    done
}

change_ip() {
    read_servers
    if ! select_servers; then return; fi

    for idx in "${SELECTED_INDICES[@]}"; do
        local server=$(get_server_by_index "$idx")
        info "Current network configuration on $server:"
        ssh_to_server "$server" "ip addr show | grep -E 'inet ' | grep -v '127.0.0.1'; ip route | grep default; cat /etc/resolv.conf | grep nameserver" 2>/dev/null
        echo "----------------------------------------"
    done

    read -p "Enter new IP address (e.g., 192.168.1.100): " new_ip
    read -p "Enter new netmask (e.g., 255.255.255.0): " new_netmask
    read -p "Enter new gateway: " new_gateway
    read -p "Enter primary DNS (DNS1): " dns1
    read -p "Enter secondary DNS (DNS2): " dns2
    if [[ -z "$new_ip" || -z "$new_netmask" || -z "$new_gateway" ]]; then
        error "IP, netmask, and gateway are required."
        return
    fi

    warn "This will change the network configuration and may disconnect your SSH session."
    read -p "Are you sure you want to proceed? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        info "Aborted."
        return
    fi

    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

if [ -f /etc/debian_version ]; then
    IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -z "$IFACE" ]; then
        IFACE=$(ip addr show | grep -E '^[0-9]+: ' | grep -v lo | awk -F': ' '{print $2}' | head -1)
    fi
    echo "Using interface: $IFACE"
    $SUDO cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%Y%m%d%H%M%S)
    $SUDO tee /etc/network/interfaces <<EOL
auto lo
iface lo inet loopback
auto $IFACE
iface $IFACE inet static
    address $new_ip
    netmask $new_netmask
    gateway $new_gateway
    dns-nameservers $dns1 $dns2
EOL
    $SUDO systemctl restart networking || $SUDO service networking restart
elif [ -f /etc/redhat-release ] || [ -f /etc/SuSE-release ]; then
    IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -z "$IFACE" ]; then
        IFACE=$(ip addr show | grep -E '^[0-9]+: ' | grep -v lo | awk -F': ' '{print $2}' | head -1)
    fi
    echo "Using interface: $IFACE"
    $SUDO cp /etc/sysconfig/network-scripts/ifcfg-$IFACE /etc/sysconfig/network-scripts/ifcfg-$IFACE.bak.$(date +%Y%m%d%H%M%S)
    $SUDO tee /etc/sysconfig/network-scripts/ifcfg-$IFACE <<EOL
DEVICE=$IFACE
BOOTPROTO=none
ONBOOT=yes
IPADDR=$new_ip
NETMASK=$new_netmask
GATEWAY=$new_gateway
DNS1=$dns1
DNS2=$dns2
EOL
    $SUDO systemctl restart network || $SUDO service network restart
else
    echo "Unsupported OS for automatic network configuration."
    exit 1
fi
echo "nameserver $dns1" | $SUDO tee /etc/resolv.conf
echo "nameserver $dns2" | $SUDO tee -a /etc/resolv.conf
echo "Network configuration updated."
EOF
)
    # Ganti variabel di dalam skrip
    script=$(echo "$script" | sed "s/\$new_ip/$new_ip/g; s/\$new_netmask/$new_netmask/g; s/\$new_gateway/$new_gateway/g; s/\$dns1/$dns1/g; s/\$dns2/$dns2/g")

    for idx in "${SELECTED_INDICES[@]}"; do
        local server=$(get_server_by_index "$idx")
        info "Applying new IP configuration on $server ..."
        run_remote_script "$server" "$script"
        echo "----------------------------------------"
    done
}

# ======================================================================
# 3. Server Maintainer Functions (with sudo -i for root actions)
# ======================================================================

build_maintenance_script() {
    local debian_cmds="$1"
    local rhel_cmds="$2"
    cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi
EOF
    echo "if [ -f /etc/debian_version ]; then"
    echo "$debian_cmds" | tr ';' '\n' | sed 's/sudo/\$SUDO/g'
    echo "elif [ -f /etc/redhat-release ]; then"
    echo "$rhel_cmds" | tr ';' '\n' | sed 's/sudo/\$SUDO/g'
    echo "elif [ -f /etc/SuSE-release ]; then"
    echo "$rhel_cmds" | tr ';' '\n' | sed 's/sudo/\$SUDO/g'
    echo "else"
    echo "    echo \"Unsupported OS\""
    echo "    exit 1"
    echo "fi"
}

maintain_update() {
    local script=$(build_maintenance_script \
        "sudo apt-get update" \
        "sudo yum check-update || true")
    run_action_on_servers_sudo "$script" "Update package lists"
}

maintain_upgrade() {
    local script=$(build_maintenance_script \
        "sudo apt-get upgrade -y" \
        "sudo yum update -y")
    run_action_on_servers_sudo "$script" "Upgrade packages"
}

maintain_update_upgrade() {
    local script=$(build_maintenance_script \
        "sudo apt-get update && sudo apt-get upgrade -y" \
        "sudo yum check-update || true && sudo yum update -y")
    run_action_on_servers_sudo "$script" "Update & Upgrade"
}

# ======================================================================
# Clean cache & clear memory (gabungan)
# ======================================================================
maintain_clean_cache_memory() {
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

echo "Cleaning system cache and memory caches..."

# Clean package cache
if [ -f /etc/debian_version ]; then
    $SUDO apt-get clean
    $SUDO apt-get autoclean
elif [ -f /etc/redhat-release ] || [ -f /etc/SuSE-release ]; then
    $SUDO yum clean all
    $SUDO dnf clean all 2>/dev/null || true
else
    echo "Unsupported OS for package cache cleaning"
fi

# Clear memory caches (requires root)
sync
echo 3 | $SUDO tee /proc/sys/vm/drop_caches >/dev/null
echo "Memory caches cleared."

echo "Cache and memory cleanup completed."
EOF
)
    run_action_on_servers_sudo "$script" "Clean cache & clear memory"
}

# ======================================================================
# Clean logs – langsung jalankan pembersihan umum (tanpa pilihan)
# ======================================================================
maintain_clean_logs() {
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

echo "Cleaning system logs and archives..."

# Kumpulkan direktori yang akan dibersihkan
log_dirs=()
[ -d /var/log ] && log_dirs+=("/var/log")
[ -d /var/backups ] && log_dirs+=("/var/backups")
[ -d /usr/local/cpanel/logs ] && log_dirs+=("/usr/local/cpanel/logs")
for home_dir in /home/*; do
    [ -d "$home_dir/logs" ] && log_dirs+=("$home_dir/logs")
done

# Fungsi menghitung total ukuran (dalam bytes) dari semua direktori
get_total_size() {
    local sum=0
    for d in "${log_dirs[@]}"; do
        if [ -d "$d" ]; then
            size=$(du -sb "$d" 2>/dev/null | awk '{print $1}')
            sum=$((sum + size))
        fi
    done
    echo $sum
}

# Fungsi menghitung jumlah file .gz
count_gz_files() {
    local count=0
    for d in "${log_dirs[@]}"; do
        if [ -d "$d" ]; then
            c=$(find "$d" -type f -name "*.gz" 2>/dev/null | wc -l)
            count=$((count + c))
        fi
    done
    echo $count
}

# Catat ukuran dan jumlah file sebelum pembersihan
initial_size=$(get_total_size)
initial_gz=$(count_gz_files)

# --- Proses pembersihan ---
# 1. Hapus semua file .gz
for d in "${log_dirs[@]}"; do
    find "$d" -type f -name "*.gz" -delete 2>/dev/null
done

# 2. Kosongkan file log (*_log dan *.log)
for d in "${log_dirs[@]}"; do
    find "$d" -type f \( -name "*_log" -o -name "*.log" \) -exec truncate -s 0 {} + 2>/dev/null
done

# 3. Hapus file log lama (> 14 hari) di /var/log
find /var/log -name '*.log' -type f -mtime +14 -delete 2>/dev/null || true

# 4. Vacuum journal (batasi ukuran 100M) – butuh sudo
$SUDO journalctl --vacuum-size=100M 2>/dev/null || true

# --- Catat ukuran dan jumlah file setelah pembersihan ---
final_size=$(get_total_size)
final_gz=$(count_gz_files)

# Hitung selisih
freed=$((initial_size - final_size))
gz_removed=$((initial_gz - final_gz))

# Fungsi konversi byte ke format human-readable (jika numfmt tidak tersedia)
format_size() {
    local bytes=$1
    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec "$bytes" 2>/dev/null || echo "${bytes} B"
    else
        if [ $bytes -ge 1073741824 ]; then
            echo "$(echo "scale=2; $bytes/1073741824" | bc) GB"
        elif [ $bytes -ge 1048576 ]; then
            echo "$(echo "scale=2; $bytes/1048576" | bc) MB"
        elif [ $bytes -ge 1024 ]; then
            echo "$(echo "scale=2; $bytes/1024" | bc) KB"
        else
            echo "${bytes} B"
        fi
    fi
}

# Tampilkan ringkasan
echo "========================================="
echo "           CLEANUP SUMMARY"
echo "========================================="
echo "  Directories cleaned : ${#log_dirs[@]}"
echo "  .gz files removed   : $gz_removed"
echo "  Total space freed   : $(format_size $freed)"
echo "  Initial total size  : $(format_size $initial_size)"
echo "  Final total size    : $(format_size $final_size)"
echo "========================================="
EOF
)
    run_action_on_servers_sudo "$script" "Clean system logs"
}

maintain_repair_packages() {
    local script=$(build_maintenance_script \
        "sudo dpkg --configure -a; sudo apt --fix-broken install -y; sudo apt autoremove -y; sudo apt autoclean" \
        "sudo rpm --rebuilddb; sudo yum clean all; sudo package-cleanup --cleandupes 2>/dev/null || true; sudo yum-complete-transaction 2>/dev/null || true")
    run_action_on_servers_sudo "$script" "Repair package management"
}

maintain_pending_updates() {
    local script=$(build_maintenance_script \
        "sudo apt-get update 2>/dev/null; sudo apt-get --just-print upgrade | grep -E '^Inst' || echo 'No pending updates'" \
        "sudo yum check-update | grep -E '^[a-zA-Z0-9]' || echo 'No pending updates'")
    run_action_on_servers_sudo "$script" "Check pending updates"
}

maintain_check_reboot() {
    local script=$(cat <<'EOF'
#!/bin/bash
if [ -f /var/run/reboot-required ]; then
    echo "Reboot required (Debian/Ubuntu)."
elif [ -f /boot/grub/grub.conf ] && [ -f /var/run/reboot-required ]; then
    echo "Reboot required (RHEL)."
else
    echo "No reboot pending."
fi
if [ -f /proc/version ] && [ -f /boot/vmlinuz-* ]; then
    current=$(uname -r)
    latest=$(ls -t /boot/vmlinuz-* | head -1 | sed 's/.*vmlinuz-//')
    if [ "$current" != "$latest" ]; then
        echo "A newer kernel is installed, reboot may be needed to use it."
    fi
fi
EOF
)
    run_action_on_servers "$script" "Check pending reboot"
}

# ======================================================================
# 4. Server Information
# ======================================================================

# Fungsi untuk menampilkan informasi server menggunakan tecmint_monitor style
show_server_info() {
    local server="$1"
    info "System Information for $server"
    echo "----------------------------------------"
    ssh_to_server "$server" "bash -s" <<'EOF'
#!/bin/bash
# =============================================================================
# System Monitor Script (Remote) - Enhanced Version
# =============================================================================

set -euo pipefail 2>/dev/null || true

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# Check if running as root
# -----------------------------------------------------------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${YELLOW}Warning: Some information may require root privileges${NC}"
    fi
}

# -----------------------------------------------------------------------------
# Display Date/Time
# -----------------------------------------------------------------------------
show_datetime() {
    echo -e "${CYAN}▶ Date/Time:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
}

# -----------------------------------------------------------------------------
# Check internet connection
# -----------------------------------------------------------------------------
check_internet() {
    echo -e "${CYAN}▶ Internet Status:${NC}"
    if ping -c 1 google.com &>/dev/null || ping -c 1 8.8.8.8 &>/dev/null; then
        echo -e "  ${GREEN}✓ Connected${NC}"
    else
        echo -e "  ${RED}✗ Disconnected${NC}"
    fi
    echo ""
}

# -----------------------------------------------------------------------------
# Display OS information
# -----------------------------------------------------------------------------
show_os_info() {
    echo -e "${CYAN}▶ Operating System:${NC}"
    
    # OS Type
    os_type=$(uname -o 2>/dev/null || echo "Unknown")
    echo -e "  ${BOLD}Type:${NC} $os_type"
    
    # OS Name and Version
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release 2>/dev/null || true
        echo -e "  ${BOLD}Name:${NC} ${NAME:-Unknown}"
        echo -e "  ${BOLD}Version:${NC} ${VERSION:-Unknown}"
    elif [[ -f /etc/redhat-release ]]; then
        echo -e "  ${BOLD}Name:${NC} $(cat /etc/redhat-release)"
    else
        echo -e "  ${YELLOW}Name: Could not determine${NC}"
    fi
    
    # Architecture
    arch=$(uname -m)
    echo -e "  ${BOLD}Architecture:${NC} $arch"
    
    # Kernel
    kernel=$(uname -r)
    echo -e "  ${BOLD}Kernel:${NC} $kernel"
    
    # Hostname
    hostname=$(hostname 2>/dev/null || echo "Unknown")
    echo -e "  ${BOLD}Hostname:${NC} $hostname"
    
    echo ""
}

# -----------------------------------------------------------------------------
# Display network information
# -----------------------------------------------------------------------------
show_network() {
    echo -e "${CYAN}▶ Network Information:${NC}"
    
    # Internal IP
    internal_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [[ -n "$internal_ip" ]]; then
        echo -e "  ${BOLD}Internal IP:${NC} $internal_ip"
    else
        echo -e "  ${YELLOW}Internal IP: Not available${NC}"
    fi
    
    # DNS Servers
    if [[ -f /etc/resolv.conf ]]; then
        dns=$(grep -E '^nameserver' /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')
        echo -e "  ${BOLD}DNS Servers:${NC} ${dns:-Not configured}"
    fi
    
    echo ""
}

# -----------------------------------------------------------------------------
# Display logged in users
# -----------------------------------------------------------------------------
show_users() {
    echo -e "${CYAN}▶ Logged In Users:${NC}"
    if command -v who &>/dev/null; then
        who | while read -r line; do
            echo "  $line"
        done
    else
        echo "  ${YELLOW}Command 'who' not available${NC}"
    fi
    echo ""
}

# -----------------------------------------------------------------------------
# Display memory usage
# -----------------------------------------------------------------------------
show_memory() {
    echo -e "${CYAN}▶ Memory Usage:${NC}"
    
    if command -v free &>/dev/null; then
        # RAM
        echo -e "  ${BOLD}RAM:${NC}"
        free -h | grep -E '^Mem:' | while read -r line; do
            total=$(echo "$line" | awk '{print $2}')
            used=$(echo "$line" | awk '{print $3}')
            free=$(echo "$line" | awk '{print $4}')
            available=$(echo "$line" | awk '{print $7}')
            echo -e "    Total: ${GREEN}$total${NC} | Used: ${YELLOW}$used${NC} | Free: ${BLUE}$free${NC} | Available: ${GREEN}$available${NC}"
        done
        
        # Swap
        echo -e "  ${BOLD}Swap:${NC}"
        free -h | grep -E '^Swap:' | while read -r line; do
            total=$(echo "$line" | awk '{print $2}')
            used=$(echo "$line" | awk '{print $3}')
            free=$(echo "$line" | awk '{print $4}')
            echo -e "    Total: ${GREEN}$total${NC} | Used: ${YELLOW}$used${NC} | Free: ${BLUE}$free${NC}"
        done
    else
        echo -e "  ${YELLOW}Memory info not available${NC}"
    fi
    
    echo ""
}

# -----------------------------------------------------------------------------
# Display disk usage
# -----------------------------------------------------------------------------
show_disk() {
    echo -e "${CYAN}▶ Disk Usage:${NC}"
    
    if command -v df &>/dev/null; then
        df -h | grep -E '^(Filesystem|/dev/)' | while read -r line; do
            if [[ "$line" == Filesystem* ]]; then
                echo "  $line"
            else
                # Ekstrak persentase penggunaan
                usage=$(echo "$line" | awk '{print $5}' | sed 's/%//')
                # Tentukan warna berdasarkan persentase
                if [[ $usage -gt 90 ]]; then
                    color="$RED"
                elif [[ $usage -gt 75 ]]; then
                    color="$YELLOW"
                else
                    color="$GREEN"
                fi
                # Tampilkan baris dengan warna pada persentase saja
                # Gunakan awk untuk membangun ulang baris dengan warna
                size=$(echo "$line" | awk '{print $2}')
                used=$(echo "$line" | awk '{print $3}')
                avail=$(echo "$line" | awk '{print $4}')
                mount=$(echo "$line" | awk '{print $6}')
                echo -e "  $size  $used  $avail  ${color}${usage}%${NC}  $mount"
            fi
        done
    else
        echo -e "  ${YELLOW}Disk info not available${NC}"
    fi
    
    echo ""
}

# -----------------------------------------------------------------------------
# Display load average
# -----------------------------------------------------------------------------
show_load() {
    echo -e "${CYAN}▶ Load Average:${NC}"
    
    if command -v uptime &>/dev/null; then
        load=$(uptime | awk -F'load average:' '{print $2}' | sed 's/^ //')
        echo "  $load"
        
        # Interpret load
        cpu_cores=$(nproc 2>/dev/null || echo 1)
        load_1min=$(echo "$load" | awk '{print $1}' | sed 's/,//')
        if command -v bc &>/dev/null && (( $(echo "$load_1min > $cpu_cores" | bc -l 2>/dev/null || echo 0) )); then
            echo -e "  ${YELLOW}⚠️  Load is high (${cpu_cores} cores available)${NC}"
        else
            echo -e "  ${GREEN}✓ Load is normal${NC}"
        fi
    else
        echo -e "  ${YELLOW}Load average not available${NC}"
    fi
    
    echo ""
}

# -----------------------------------------------------------------------------
# Display uptime
# -----------------------------------------------------------------------------
show_uptime() {
    echo -e "${CYAN}▶ System Uptime:${NC}"
    
    if command -v uptime &>/dev/null; then
        uptime -p 2>/dev/null || uptime | awk '{print $3,$4,$5}' | sed 's/,//'
    else
        echo -e "  ${YELLOW}Uptime not available${NC}"
    fi
    
    echo ""
}

# -----------------------------------------------------------------------------
# Display top processes
# -----------------------------------------------------------------------------
show_processes() {
    echo -e "${CYAN}▶ Top 5 CPU Processes:${NC}"
    
    if command -v ps &>/dev/null; then
        ps aux --sort=-%cpu 2>/dev/null | head -6 | tail -5 | while read -r line; do
            cpu=$(echo "$line" | awk '{print $3}')
            mem=$(echo "$line" | awk '{print $4}')
            cmd=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}' | cut -c1-50)
            echo -e "  CPU: ${GREEN}${cpu}%${NC} MEM: ${BLUE}${mem}%${NC} CMD: ${cmd}"
        done
    else
        echo -e "  ${YELLOW}Process info not available${NC}"
    fi
    
    echo ""
}

# -----------------------------------------------------------------------------
# Display service status
# -----------------------------------------------------------------------------
show_services() {
    echo -e "${CYAN}▶ Critical Services:${NC}"
    
    services=("nginx" "apache2" "httpd" "mysql" "mysqld" "php-fpm" "redis" "ssh" "docker")
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $service is running"
        elif systemctl is-active --quiet "$service.service" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $service is running"
        elif pgrep -x "$service" &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $service is running"
        fi
    done
    
    echo ""
}

# -----------------------------------------------------------------------------
# Display last logins
# -----------------------------------------------------------------------------
show_last_logins() {
    echo -e "${CYAN}▶ Recent Logins (last 5):${NC}"
    
    if command -v last &>/dev/null; then
        last -n 5 2>/dev/null | head -5 | while read -r line; do
            echo "  $line"
        done
    else
        echo -e "  ${YELLOW}Login history not available${NC}"
    fi
    
    echo ""
}

# -----------------------------------------------------------------------------
# Main function
# -----------------------------------------------------------------------------
main() {
    check_root
    show_datetime
    check_internet
    show_os_info
    show_network
    show_users
    show_memory
    show_disk
    show_load
    show_uptime
    show_processes
    show_services
    show_last_logins
}

main
EOF
    echo "----------------------------------------"
}

info_server() {
    read_servers
    if ! select_servers; then return; fi
    for idx in "${SELECTED_INDICES[@]}"; do
        local server=$(get_server_by_index "$idx")
        show_server_info "$server"
    done
}

info_partition_disk() {
    run_info_command_sudo "fdisk -l 2>/dev/null || echo 'fdisk not available or permission denied'" "Check partition disk"
}

info_disk_structure() {
    run_info_command "lsblk -f 2>/dev/null || echo 'lsblk not available'" "Check disk structure (filesystem)"
}

info_uuid_fstype() {
    run_info_command_sudo "blkid 2>/dev/null || echo 'blkid not available or permission denied'" "Check UUID & filesystem type"
}

# ======================================================================
# 5. User Management
# ======================================================================

run_user_command() {
    local script="$1"
    local desc="$2"
    run_action_on_servers_sudo "$script" "$desc"
}

user_list() {
    local script=$(cat <<'EOF'
#!/bin/bash
if [ -f /etc/debian_version ]; then
    echo "Human users (uid>=1000):"
    getent passwd | awk -F: '$3>=1000 {print $1}' | sort
    echo "--- System users (uid<1000) ---"
    getent passwd | awk -F: '$3<1000 {print $1}' | head -20
else
    echo "Human users (uid>=1000):"
    getent passwd | awk -F: '$3>=1000 {print $1}' | sort
    echo "--- System users (uid<1000) ---"
    getent passwd | awk -F: '$3<1000 {print $1}' | head -20
fi
EOF
)
    run_user_command "$script" "User list"
}

user_add() {
    read -p "Enter username to add: " username
    if [[ -z "$username" ]]; then
        error "Username cannot be empty."
        return
    fi
    read -s -p "Enter password for $username: " password
    echo
    read -s -p "Confirm password: " password2
    echo
    if [[ "$password" != "$password2" ]]; then
        error "Passwords do not match."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

if id "$username" &>/dev/null; then
    echo "User $username already exists."
    exit 1
fi
if [ -f /etc/debian_version ]; then
    useradd -m -s /bin/bash "$username"
    echo "$username:$password" | chpasswd
else
    useradd -m -s /bin/bash "$username"
    echo "$password" | passwd --stdin "$username"
fi
if [ $? -eq 0 ]; then
    echo "User $username created successfully."
else
    echo "Failed to create user $username."
    exit 1
fi
EOF
)
    script=$(echo "$script" | sed "s/\$username/$username/g; s/\$password/$password/g")
    run_user_command "$script" "Add user $username"
}

user_delete() {
    read -p "Enter username to delete: " username
    if [[ -z "$username" ]]; then
        error "Username cannot be empty."
        return
    fi
    read -p "Remove home directory? (y/N): " remove_home
    local home_flag=""
    if [[ $remove_home =~ ^[Yy]$ ]]; then
        home_flag="-r"
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

if ! id "$username" &>/dev/null; then
    echo "User $username does not exist."
    exit 1
fi
userdel $home_flag "$username"
if [ $? -eq 0 ]; then
    echo "User $username deleted successfully."
else
    echo "Failed to delete user $username."
    exit 1
fi
EOF
)
    script=$(echo "$script" | sed "s/\$username/$username/g")
    run_user_command "$script" "Delete user $username"
}

user_change_password() {
    read_servers
    if ! select_servers; then return; fi
    for idx in "${SELECTED_INDICES[@]}"; do
        local server=$(get_server_by_index "$idx")
        info "Fetching user list from $server ..."
        ssh_to_server "$server" "getent passwd | awk -F: '\$3>=1000 {print \$1}' | sort" 2>/dev/null
        echo "----------------------------------------"
    done
    read -p "Enter username to change password: " username
    if [[ -z "$username" ]]; then
        error "Username cannot be empty."
        return
    fi
    read -s -p "Enter current password (press Enter to skip): " oldpass
    echo
    read -s -p "Enter new password: " newpass1
    echo
    read -s -p "Confirm new password: " newpass2
    echo
    if [[ "$newpass1" != "$newpass2" ]]; then
        error "Passwords do not match."
        return
    fi
    if [[ -z "$newpass1" ]]; then
        error "Password cannot be empty."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

if ! id "$username" &>/dev/null; then
    echo "User $username does not exist."
    exit 1
fi
echo "$username:$newpass" | chpasswd
if [ $? -eq 0 ]; then
    echo "Password for $username changed successfully."
else
    echo "Failed to change password for $username."
    exit 1
fi
EOF
)
    script=$(echo "$script" | sed "s/\$username/$username/g; s/\$newpass/$newpass1/g")
    run_user_command "$script" "Change password for $username"
}

# ======================================================================
# 6. Security Management (with sudo -i)
# ======================================================================

run_security_command_sudo() {
    local script="$1"
    local desc="$2"
    run_action_on_servers_sudo "$script" "$desc"
}

sec_firewall_status() {
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

if command -v ufw >/dev/null 2>&1; then
    if systemctl is-active --quiet ufw; then
        echo "UFW is running."
    else
        echo "UFW is installed but not running (or inactive)."
    fi
    $SUDO ufw status verbose 2>/dev/null || echo "UFW status: could not retrieve."
elif command -v firewall-cmd >/dev/null 2>&1; then
    if systemctl is-active --quiet firewalld; then
        echo "firewalld is running."
        $SUDO firewall-cmd --state 2>/dev/null || echo "firewalld state unknown."
    else
        echo "firewalld is installed but not running."
    fi
else
    echo "No known firewall (UFW or firewalld) found."
fi
EOF
)
    run_security_command_sudo "$script" "Firewall status"
}

sec_firewall_service() {
    echo "Select action:"
    echo "1) Start firewall"
    echo "2) Stop firewall"
    echo "3) Restart firewall"
    read -p "Choose (1-3): " action
    local cmd=""
    case $action in
        1) cmd="start" ;;
        2) cmd="stop" ;;
        3) cmd="restart" ;;
        *) warn "Invalid choice."; return ;;
    esac
    local script=$(cat <<EOF
#!/bin/bash
# Deteksi sudo
if [ "\$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

if command -v ufw >/dev/null 2>&1; then
    echo "Using UFW..."
    \$SUDO systemctl $cmd ufw
    if [ \$? -eq 0 ]; then
        echo "UFW $cmd successful."
    else
        echo "UFW $cmd failed."
    fi
elif command -v firewall-cmd >/dev/null 2>&1; then
    echo "Using firewalld..."
    \$SUDO systemctl $cmd firewalld
    if [ \$? -eq 0 ]; then
        echo "firewalld $cmd successful."
    else
        echo "firewalld $cmd failed."
    fi
else
    echo "No known firewall found."
fi
EOF
)
    run_security_command_sudo "$script" "Firewall $cmd"
}

sec_firewall_add_rule() {
    echo "Select rule type:"
    echo "1) Allow port (TCP/UDP)"
    echo "2) Drop IP"
    echo "3) Reject IP"
    read -p "Choose (1-3): " rule_type
    case $rule_type in
        1)
            read -p "Enter port number: " port
            read -p "Protocol (tcp/udp): " proto
            if [[ -z "$port" || -z "$proto" ]]; then
                error "Port and protocol required."
                return
            fi
            local script=$(cat <<EOF
#!/bin/bash
# Deteksi sudo
if [ "\$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

if command -v ufw >/dev/null 2>&1; then
    \$SUDO ufw allow $port/$proto
    if [ \$? -eq 0 ]; then
        echo "UFW rule added: allow $port/$proto"
    else
        echo "Failed to add UFW rule."
    fi
elif command -v firewall-cmd >/dev/null 2>&1; then
    \$SUDO firewall-cmd --add-port=$port/$proto --permanent
    if [ \$? -eq 0 ]; then
        \$SUDO firewall-cmd --reload
        echo "firewalld rule added: allow $port/$proto (permanent)"
    else
        echo "Failed to add firewalld rule."
    fi
else
    echo "No known firewall found."
fi
EOF
)
            run_security_command_sudo "$script" "Allow port $port/$proto"
            ;;
        2|3)
            read -p "Enter IP address: " ip
            if [[ -z "$ip" ]]; then
                error "IP address required."
                return
            fi
            local action_word=$([ $rule_type -eq 2 ] && echo "drop" || echo "reject")
            local script=$(cat <<EOF
#!/bin/bash
# Deteksi sudo
if [ "\$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

if command -v ufw >/dev/null 2>&1; then
    \$SUDO ufw $action_word from $ip
    if [ \$? -eq 0 ]; then
        echo "UFW rule added: $action_word from $ip"
    else
        echo "Failed to add UFW rule."
    fi
elif command -v firewall-cmd >/dev/null 2>&1; then
    \$SUDO firewall-cmd --direct --add-rule ipv4 filter INPUT 0 -s $ip -j $action_word
    if [ \$? -eq 0 ]; then
        \$SUDO firewall-cmd --direct --add-rule ipv6 filter INPUT 0 -s $ip -j $action_word 2>/dev/null
        \$SUDO firewall-cmd --runtime-to-permanent
        echo "firewalld rule added: $action_word from $ip (direct)"
    else
        echo "Failed to add firewalld rule."
    fi
else
    echo "No known firewall found."
fi
EOF
)
            run_security_command_sudo "$script" "$action_word IP $ip"
            ;;
        *) warn "Invalid choice."; return ;;
    esac
}

sec_virus_scan() {
    read -p "Enter folder path to scan (default /home): " folder
    [[ -z "$folder" ]] && folder="/home"
    local scan_script=$(cat <<EOF
#!/bin/bash
# Deteksi sudo
if [ "\$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

if ! command -v clamscan >/dev/null 2>&1; then
    echo "clamscan not found. Installing..."
    if [ -f /etc/debian_version ]; then
        \$SUDO apt-get update && \$SUDO apt-get install -y clamav clamav-daemon
    elif [ -f /etc/redhat-release ]; then
        \$SUDO yum install -y epel-release && \$SUDO yum install -y clamav clamav-update
    else
        echo "Unsupported OS. Cannot install clamav automatically."
        exit 1
    fi
    if command -v freshclam >/dev/null 2>&1; then
        \$SUDO freshclam
    fi
fi
if command -v clamscan >/dev/null 2>&1; then
    echo "Starting virus scan on $folder (this may take a while)..."
    \$SUDO clamscan -r --bell -i "$folder" 2>&1
    echo "Scan completed."
else
    echo "clamscan still not available. Aborting scan."
    exit 1
fi
EOF
)
    scan_script=$(echo "$scan_script" | sed "s|\$folder|$folder|g")
    run_security_command_sudo "$scan_script" "Virus scan on $folder"
}

sec_failed_logins() {
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo (untuk lastb)
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

echo "Recent failed login attempts (last 20):"
$SUDO lastb -n 20 2>/dev/null || echo "lastb command not available or permission denied."
echo "---"
echo "Failed SSH authentication attempts from /var/log/auth.log (last 10):"
if [ -f /var/log/auth.log ]; then
    grep "Failed password" /var/log/auth.log | tail -10
elif [ -f /var/log/secure ]; then
    grep "Failed password" /var/log/secure | tail -10
else
    echo "No auth log found."
fi
EOF
)
    run_security_command_sudo "$script" "Check failed logins"
}

sec_open_ports() {
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo (untuk netstat/ss)
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

echo "Listening ports and associated services:"
$SUDO ss -tulpn | grep LISTEN 2>/dev/null || $SUDO netstat -tulpn | grep LISTEN 2>/dev/null || echo "ss/netstat not available."
EOF
)
    run_security_command_sudo "$script" "Check open ports"
}

# ----------------------------------------------------------------------
# SSL Certificate Management
# ----------------------------------------------------------------------

sec_ssl_install_certbot() {
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

if command -v certbot >/dev/null 2>&1; then
    echo "Certbot already installed: $(certbot --version 2>/dev/null)"
    return 0
fi
echo "Certbot not found. Installing..."
if [ -f /etc/debian_version ]; then
    $SUDO apt-get update
    $SUDO apt-get install -y certbot python3-certbot-nginx python3-certbot-apache
elif [ -f /etc/redhat-release ]; then
    $SUDO yum install -y epel-release
    $SUDO yum install -y certbot python3-certbot-nginx python3-certbot-apache
elif [ -f /etc/SuSE-release ]; then
    $SUDO zypper install -y certbot python3-certbot-nginx python3-certbot-apache
else
    echo "Unsupported OS. Please install certbot manually."
    exit 1
fi
if command -v certbot >/dev/null 2>&1; then
    echo "Certbot installed successfully."
else
    echo "Certbot installation failed."
    exit 1
fi
EOF
)
    run_security_command_sudo "$script" "Install Certbot (Let's Encrypt)"
}

sec_ssl_get_cert() {
    read -p "Enter domain name (e.g., example.com): " domain
    if [[ -z "$domain" ]]; then
        error "Domain required."
        return
    fi
    read -p "Enter email address for notifications: " email
    if [[ -z "$email" ]]; then
        error "Email required."
        return
    fi
    read -p "Choose web server type (nginx/apache/standalone) [nginx]: " webserver
    [[ -z "$webserver" ]] && webserver="nginx"
    local script=$(cat <<EOF
#!/bin/bash
# Deteksi sudo
if [ "\$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

if ! command -v certbot >/dev/null 2>&1; then
    echo "Certbot not installed. Please install first (option 1)."
    exit 1
fi
if [ "$webserver" == "standalone" ]; then
    \$SUDO systemctl stop nginx 2>/dev/null || \$SUDO systemctl stop apache2 2>/dev/null || true
fi
echo "Obtaining certificate for $domain ..."
\$SUDO certbot certonly --$webserver -d $domain --non-interactive --agree-tos -m $email
if [ \$? -eq 0 ]; then
    echo "Certificate obtained successfully."
    echo "Files: /etc/letsencrypt/live/$domain/"
    if [ "$webserver" == "standalone" ]; then
        \$SUDO systemctl start nginx 2>/dev/null || \$SUDO systemctl start apache2 2>/dev/null || true
    fi
else
    echo "Failed to obtain certificate."
    exit 1
fi
EOF
)
    run_security_command_sudo "$script" "Get Let's Encrypt certificate for $domain"
}

sec_ssl_renew_cert() {
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

if ! command -v certbot >/dev/null 2>&1; then
    echo "Certbot not installed. Please install first."
    exit 1
fi
$SUDO certbot renew --quiet
if [ $? -eq 0 ]; then
    echo "Certificates renewed successfully (if any were due)."
else
    echo "Renewal failed or no certificates to renew."
fi
EOF
)
    run_security_command_sudo "$script" "Renew Let's Encrypt certificates"
}

sec_ssl_check_expiry() {
    read -p "Enter domain to check (or leave empty to check all): " domain
    local script
    if [[ -z "$domain" ]]; then
        script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

if ! command -v certbot >/dev/null 2>&1; then
    echo "Certbot not installed."
    exit 1
fi
$SUDO certbot certificates 2>/dev/null | grep -E "Domain:|Expiry Date:" || echo "No certificates found or certbot error."
EOF
)
    else
        script=$(cat <<EOF
#!/bin/bash
# Deteksi sudo
if [ "\$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

if ! command -v certbot >/dev/null 2>&1; then
    echo "Certbot not installed."
    exit 1
fi
\$SUDO certbot certificates 2>/dev/null | grep -A 10 "Domain: $domain" || echo "Certificate for $domain not found."
EOF
)
    fi
    run_security_command_sudo "$script" "Check certificate expiry"
}

sec_ssl_list_certs() {
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

if ! command -v certbot >/dev/null 2>&1; then
    echo "Certbot not installed."
    exit 1
fi
$SUDO certbot certificates 2>/dev/null || echo "No certificates found."
EOF
)
    run_security_command_sudo "$script" "List all SSL certificates"
}

sec_ssl_auto_renew() {
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

if ! command -v certbot >/dev/null 2>&1; then
    echo "Certbot not installed."
    exit 1
fi
(crontab -l 2>/dev/null | grep -v "certbot renew"; echo "0 0,12 * * * /usr/bin/certbot renew --quiet") | $SUDO crontab -
if [ $? -eq 0 ]; then
    echo "Cron job added for automatic renewal (twice daily)."
else
    echo "Failed to add cron job."
fi
EOF
)
    run_security_command_sudo "$script" "Setup auto-renewal (cron job)"
}

sec_ssl_menu() {
    while true; do
        echo
        echo "===== SSL Certificate Management (Let's Encrypt) ====="
        echo "1. Install Certbot (Let's Encrypt client)"
        echo "2. Get new certificate for domain"
        echo "3. Renew all certificates"
        echo "4. Check certificate expiry"
        echo "5. List all certificates"
        echo "6. Setup auto-renewal (cron job)"
        echo "0. Back to Security Management"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) sec_ssl_install_certbot ;;
            2) sec_ssl_get_cert ;;
            3) sec_ssl_renew_cert ;;
            4) sec_ssl_check_expiry ;;
            5) sec_ssl_list_certs ;;
            6) sec_ssl_auto_renew ;;
            0) break ;;
            *) warn "Invalid option." ;;
        esac
    done
}

# ======================================================================
# 7. Service Management
# ======================================================================

run_service_command() {
    local cmd="$1"
    local desc="$2"
    read_servers
    if ! select_servers; then return; fi
    for idx in "${SELECTED_INDICES[@]}"; do
        local server=$(get_server_by_index "$idx")
        info "$desc on $server"
        echo "----------------------------------------"
        # Kirim perintah dengan deteksi sudo
        ssh_to_server "$server" "bash -c 'if [ \$(id -u) -eq 0 ]; then SUDO=\"\"; else SUDO=\"sudo\"; fi; \$SUDO systemctl $cmd 2>/dev/null || echo \"systemctl not available or permission denied\"'" 2>&1
        echo "----------------------------------------"
    done
}

service_status() {
    read_servers
    if ! select_servers; then return; fi
    read -p "Show all services? (y/n, default y): " show_all
    if [[ -z "$show_all" || "$show_all" =~ ^[Yy]$ ]]; then
        run_service_command "list-units --type=service --all" "Service status (all)"
    else
        read -p "Enter service name: " svc
        if [[ -z "$svc" ]]; then warn "No service name."; return; fi
        for idx in "${SELECTED_INDICES[@]}"; do
            local server=$(get_server_by_index "$idx")
            info "Status of $svc on $server"
            ssh_to_server "$server" "bash -c 'if [ \$(id -u) -eq 0 ]; then SUDO=\"\"; else SUDO=\"sudo\"; fi; \$SUDO systemctl status $svc 2>/dev/null || echo \"Service not found or systemctl unavailable\"'" 2>&1
        done
    fi
}

service_stop() {
    read_servers
    if ! select_servers; then return; fi
    read -p "Enter service name to stop: " svc
    if [[ -z "$svc" ]]; then warn "No service name."; return; fi
    run_service_command "stop $svc" "Stopping $svc"
}

service_start() {
    read_servers
    if ! select_servers; then return; fi
    read -p "Enter service name to start: " svc
    if [[ -z "$svc" ]]; then warn "No service name."; return; fi
    run_service_command "start $svc" "Starting $svc"
}

service_restart() {
    read_servers
    if ! select_servers; then return; fi
    read -p "Enter service name to restart: " svc
    if [[ -z "$svc" ]]; then warn "No service name."; return; fi
    run_service_command "restart $svc" "Restarting $svc"
}

service_auto_start() {
    read_servers
    if ! select_servers; then return; fi
    read -p "Enter service name to auto-start if down: " svc
    if [[ -z "$svc" ]]; then warn "No service name."; return; fi
    for idx in "${SELECTED_INDICES[@]}"; do
        local server=$(get_server_by_index "$idx")
        info "Checking $svc on $server"
        status=$(ssh_to_server "$server" "systemctl is-active $svc 2>/dev/null")
        if [[ "$status" == "active" ]]; then
            echo "$svc is already running."
        else
            info "$svc is not running. Starting..."
            ssh_to_server "$server" "bash -c 'if [ \$(id -u) -eq 0 ]; then SUDO=\"\"; else SUDO=\"sudo\"; fi; \$SUDO systemctl start $svc 2>/dev/null && echo \"Started\" || echo \"Failed to start\"'"
        fi
        echo "----------------------------------------"
    done
}

# ======================================================================
# 8. Mailserver Management
# ======================================================================

run_mail_command() {
    local script="$1"
    local desc="$2"
    run_action_on_servers_sudo "$script" "$desc"
}

mail_check_mx() {
    read -p "Enter domain to check MX record (e.g., example.com): " domain
    if [[ -z "$domain" ]]; then
        error "Domain required."
        return
    fi
    local script=$(cat <<EOF
#!/bin/bash
# Deteksi sudo (tidak diperlukan untuk dig/nslookup, tapi kita sertakan)
if [ "\$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

if command -v dig >/dev/null 2>&1; then
    dig $domain MX +short
elif command -v nslookup >/dev/null 2>&1; then
    nslookup -type=MX $domain 2>/dev/null | grep 'mail exchanger'
else
    echo "Neither dig nor nslookup found. Please install dnsutils."
    exit 1
fi
EOF
)
    run_mail_command "$script" "Check MX record for $domain"
}

mail_check_ptr() {
    read -p "Enter IP address to check PTR: " ip
    if [[ -z "$ip" ]]; then
        error "IP required."
        return
    fi
    local script=$(cat <<EOF
#!/bin/bash
if [ "\$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

if command -v dig >/dev/null 2>&1; then
    dig -x $ip +short
elif command -v nslookup >/dev/null 2>&1; then
    nslookup $ip 2>/dev/null | grep 'name ='
else
    echo "Neither dig nor nslookup found."
    exit 1
fi
EOF
)
    run_mail_command "$script" "Check PTR record for $ip"
}

mail_dkim() {
    read -p "Enter domain for DKIM: " domain
    if [[ -z "$domain" ]]; then
        error "Domain required."
        return
    fi
    read -p "Enter selector (default: default): " selector
    [[ -z "$selector" ]] && selector="default"
    local script=$(cat <<EOF
#!/bin/bash
if [ "\$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

if command -v opendkim-genkey >/dev/null 2>&1; then
    if [ -f /etc/opendkim/keys/$domain/$selector.txt ]; then
        echo "DKIM key already exists for $domain (selector $selector):"
        cat /etc/opendkim/keys/$domain/$selector.txt
        echo "---"
        echo "Do you want to regenerate? (y/N): "
        read -r ans
        if [[ ! \$ans =~ ^[Yy]$ ]]; then
            echo "Skipping regeneration."
            exit 0
        fi
    fi
    echo "Generating DKIM key for $domain with selector $selector ..."
    mkdir -p /etc/opendkim/keys/$domain
    opendkim-genkey -D /etc/opendkim/keys/$domain -d $domain -s $selector
    chown opendkim:opendkim /etc/opendkim/keys/$domain/*
    echo "DKIM key generated:"
    cat /etc/opendkim/keys/$domain/$selector.txt
    echo "---"
    echo "Add this TXT record to your DNS."
elif command -v rspamadm >/dev/null 2>&1; then
    echo "Using rspamd to generate DKIM key..."
    rspamadm dkim_keygen -d $domain -s $selector
else
    echo "No DKIM generation tool found. Please install opendkim-tools or rspamd."
    echo "Try: apt-get install opendkim-tools (Debian) or yum install opendkim-tools (RHEL)"
    exit 1
fi
EOF
)
    run_mail_command "$script" "DKIM check/generate for $domain"
}

mail_spf() {
    read -p "Enter domain for SPF: " domain
    if [[ -z "$domain" ]]; then
        error "Domain required."
        return
    fi
    local script=$(cat <<EOF
#!/bin/bash
if [ "\$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

if command -v dig >/dev/null 2>&1; then
    current=\$(dig $domain TXT +short | grep -i 'v=spf1')
    if [ -n "\$current" ]; then
        echo "Current SPF record:"
        echo "\$current"
    else
        echo "No SPF record found."
    fi
    echo "---"
    echo "Recommended SPF record (adjust IPs/mail servers):"
    echo "v=spf1 mx ~all"
    echo "Or more specific: v=spf1 ip4:YOUR_IP include:spf.example.com ~all"
    echo "You can add this as a TXT record for domain $domain."
else
    echo "dig not found."
fi
EOF
)
    run_mail_command "$script" "SPF check/generate for $domain"
}

mail_dmarc() {
    read -p "Enter domain for DMARC: " domain
    if [[ -z "$domain" ]]; then
        error "Domain required."
        return
    fi
    local script=$(cat <<EOF
#!/bin/bash
if [ "\$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

if command -v dig >/dev/null 2>&1; then
    current=\$(dig _dmarc.$domain TXT +short | grep -i 'v=DMARC1')
    if [ -n "\$current" ]; then
        echo "Current DMARC record:"
        echo "\$current"
    else
        echo "No DMARC record found."
    fi
    echo "---"
    echo "Recommended DMARC record (adjust policy):"
    echo "v=DMARC1; p=none; rua=mailto:dmarc-reports@$domain; ruf=mailto:dmarc-forensic@$domain; sp=none"
    echo "You can add this as a TXT record for _dmarc.$domain."
else
    echo "dig not found."
fi
EOF
)
    run_mail_command "$script" "DMARC check/generate for $domain"
}

mail_menu() {
    while true; do
        echo
        echo "===== Mailserver Management ====="
        echo "1. Check MX record"
        echo "2. Check PTR record (reverse DNS)"
        echo "3. Check DKIM key & generate (if missing)"
        echo "4. Check SPF key & generate (if missing)"
        echo "5. Check DMARC key & generate (if missing)"
        echo "0. Back to Main Menu"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) mail_check_mx ;;
            2) mail_check_ptr ;;
            3) mail_dkim ;;
            4) mail_spf ;;
            5) mail_dmarc ;;
            0) break ;;
            *) warn "Invalid option." ;;
        esac
    done
}

# ======================================================================
# 9. Network Tools (Local)
# ======================================================================

run_local_net_tool() {
    local cmd="$1"
    local args="$2"
    local desc="$3"
    if ! install_package_local "$cmd"; then
        warn "Skipping $desc"
        return 1
    fi
    echo "--- $desc ---"
    eval "$cmd $args"
    echo "--- Done ---"
}

net_ping_subnet() {
    read -p "Enter subnet (e.g., 192.168.1.0/24): " subnet
    if [[ -z "$subnet" ]]; then
        error "Subnet required."
        return
    fi
    if ! install_package_local "nmap"; then
        warn "nmap required for ping subnet scan."
        return
    fi
    echo "Scanning subnet $subnet (ping sweep)..."
    sudo nmap -sn "$subnet" | grep -E "Nmap scan|Host" | grep -v "Host is up" 2>/dev/null || \
    nmap -sn "$subnet" | grep -E "Nmap scan|Host" | grep -v "Host is up"
}

net_traceroute() {
    read -p "Enter destination (IP or domain): " dest
    if [[ -z "$dest" ]]; then
        error "Destination required."
        return
    fi
    run_local_net_tool "traceroute" "$dest" "Traceroute to $dest"
}

net_dig() {
    read -p "Enter domain to dig: " domain
    if [[ -z "$domain" ]]; then
        error "Domain required."
        return
    fi
    run_local_net_tool "dig" "$domain any" "Dig $domain (ANY)"
}

net_nslookup() {
    read -p "Enter domain/IP to nslookup: " target
    if [[ -z "$target" ]]; then
        error "Target required."
        return
    fi
    run_local_net_tool "nslookup" "$target" "nslookup $target"
}

net_netstat() {
    run_local_net_tool "netstat" "-tulpn" "Netstat listening ports"
}

net_mx_check() {
    read -p "Enter domain to check MX: " domain
    if [[ -z "$domain" ]]; then
        error "Domain required."
        return
    fi
    run_local_net_tool "dig" "$domain MX +short" "MX record for $domain"
}

net_ptr_check() {
    read -p "Enter IP to check PTR: " ip
    if [[ -z "$ip" ]]; then
        error "IP required."
        return
    fi
    run_local_net_tool "dig" "-x $ip +short" "PTR record for $ip"
}

net_nslookup_interactive() {
    run_local_net_tool "nslookup" "" "nslookup (interactive - enter commands, Ctrl+D to exit)"
}

net_whois() {
    read -p "Enter IP or domain to whois: " target
    if [[ -z "$target" ]]; then
        error "Target required."
        return
    fi
    run_local_net_tool "whois" "$target" "whois $target"
}

network_tools_menu() {
    while true; do
        echo
        echo "===== Network Tools (Local) ====="
        echo " 1. Ping subnet (nmap ping sweep)"
        echo " 2. Traceroute"
        echo " 3. dig (DNS lookup)"
        echo " 4. nslookup"
        echo " 5. netstat (listening ports)"
        echo " 6. MX check (dig MX)"
        echo " 7. PTR check (reverse DNS)"
        echo " 8. nslookup (interactive)"
        echo " 9. whois IP/domain"
        echo " 0. Back to Main Menu"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) net_ping_subnet ;;
            2) net_traceroute ;;
            3) net_dig ;;
            4) net_nslookup ;;
            5) net_netstat ;;
            6) net_mx_check ;;
            7) net_ptr_check ;;
            8) net_nslookup_interactive ;;
            9) net_whois ;;
            0) break ;;
            *) warn "Invalid option." ;;
        esac
    done
}

# ======================================================================
# 10. APNIC Tools (Local)
# ======================================================================

apnic_install_packages() {
    install_package_local "whois"
    install_package_local "dig"
}

apnic_prefix_whois() {
    read -p "Enter IP prefix (e.g., 1.1.1.0/24): " prefix
    [[ -z "$prefix" ]] && { error "Prefix required."; return; }
    apnic_install_packages
    echo "--- Prefix Whois for $prefix ---"
    whois -h whois.apnic.net "$prefix" 2>/dev/null || whois "$prefix"
}

apnic_route_object() {
    read -p "Enter IP prefix (e.g., 1.1.1.0/24): " prefix
    [[ -z "$prefix" ]] && { error "Prefix required."; return; }
    apnic_install_packages
    echo "--- Route Object for $prefix (from RADB) ---"
    whois -h whois.radb.net "$prefix" 2>/dev/null || echo "No route object found or RADB unreachable."
}

apnic_roa() {
    read -p "Enter IP prefix (e.g., 1.1.1.0/24): " prefix
    [[ -z "$prefix" ]] && { error "Prefix required."; return; }
    apnic_install_packages
    echo "--- ROA for $prefix (via RPKI) ---"
    if command -v rpki-client >/dev/null 2>&1; then
        rpki-client -s "$prefix" 2>/dev/null || echo "No ROA data or rpki-client error."
    else
        warn "rpki-client not installed. Attempting to install..."
        sudo apt-get update && sudo apt-get install -y rpki-client 2>/dev/null || sudo yum install -y rpki-client 2>/dev/null
        if command -v rpki-client >/dev/null 2>&1; then
            rpki-client -s "$prefix" 2>/dev/null || echo "No ROA data."
        else
            echo "Cannot install rpki-client. Using whois --show-roa (limited)."
            whois -h whois.apnic.net --show-roa "$prefix" 2>/dev/null || echo "No ROA found via whois."
        fi
    fi
}

apnic_asn_info() {
    read -p "Enter AS number (e.g., 13335): " asn
    [[ -z "$asn" ]] && { error "AS number required."; return; }
    apnic_install_packages
    echo "--- ASN Info for AS$asn ---"
    whois -h whois.apnic.net "AS$asn" 2>/dev/null || whois "AS$asn"
}

apnic_rpki_validation() {
    read -p "Enter IP prefix (e.g., 1.1.1.0/24): " prefix
    read -p "Enter AS number (e.g., 13335): " asn
    [[ -z "$prefix" || -z "$asn" ]] && { error "Prefix and ASN required."; return; }
    echo "--- RPKI Validation for $prefix with AS$asn ---"
    if command -v rpki-client >/dev/null 2>&1; then
        rpki-client -s "$prefix" -a "$asn" 2>/dev/null || echo "Validation failed or no data."
    else
        warn "rpki-client not installed. Trying to install..."
        sudo apt-get update && sudo apt-get install -y rpki-client 2>/dev/null || sudo yum install -y rpki-client 2>/dev/null
        if command -v rpki-client >/dev/null 2>&1; then
            rpki-client -s "$prefix" -a "$asn" 2>/dev/null || echo "Validation failed or no data."
        else
            echo "rpki-client unavailable. Using whois --show-roa to check ROA."
            whois -h whois.apnic.net --show-roa "$prefix" 2>/dev/null | grep -i "$asn" || echo "No ROA found for this ASN/prefix."
        fi
    fi
}

apnic_asn_validation() {
    read -p "Enter AS number (e.g., 13335): " asn
    [[ -z "$asn" ]] && { error "AS number required."; return; }
    apnic_install_packages
    echo "--- ASN Validation for AS$asn ---"
    whois -h whois.apnic.net "AS$asn" 2>/dev/null | grep -i "aut-num" && echo "✓ ASN exists (valid)." || echo "✗ ASN not found or invalid."
}

apnic_ipv6() {
    read -p "Enter IPv6 address (e.g., 2001:db8::1): " ipv6
    [[ -z "$ipv6" ]] && { error "IPv6 address required."; return; }
    apnic_install_packages
    echo "--- IPv6 Info for $ipv6 ---"
    whois -h whois.apnic.net "$ipv6" 2>/dev/null || whois "$ipv6"
}

apnic_tools_menu() {
    while true; do
        echo
        echo "===== APNIC Tools (Local) ====="
        echo "1. Prefix Whois"
        echo "2. Route Object"
        echo "3. ROA (RPKI)"
        echo "4. AS Number Info"
        echo "5. RPKI Validation (prefix + ASN)"
        echo "6. AS Number Validation"
        echo "7. IPv6 Whois"
        echo "0. Back to Main Menu"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) apnic_prefix_whois ;;
            2) apnic_route_object ;;
            3) apnic_roa ;;
            4) apnic_asn_info ;;
            5) apnic_rpki_validation ;;
            6) apnic_asn_validation ;;
            7) apnic_ipv6 ;;
            0) break ;;
            *) warn "Invalid option." ;;
        esac
    done
}

# ======================================================================
# Menus
# ======================================================================

ssh_key_management_menu() {
    while true; do
        echo
        echo "===== SSH Key Management ====="
        echo "1. Add new server + import SSH key"
        echo "2. Test Passwordless SSH"
        echo "3. Import Public Key (to remote server)"
        echo "4. Generate SSH Key (local)"
        echo "5. Repair SSH Key (local & known_hosts)"
        echo "6. Remove SSH Key (from remote server)"
        echo "7. Regenerate SSH Key"
        echo "0. Back to Main Menu"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) add_new_server ;;
            2) test_passwordless ;;
            3) import_public_key ;;
            4) generate_ssh_key ;;
            5) repair_ssh_key ;;
            6) remove_ssh_key ;;
            7) regenerate_ssh_key ;;
            0) break ;;
            *) warn "Invalid option." ;;
        esac
    done
}

ssh_management_menu() {
    while true; do
        echo
        echo "===== SSH Management ====="
        echo "1. Remote SSH (manual input)"
        echo "2. Remote SSH (from server list)"
        echo "3. Change IP address (network configuration)"
        echo "0. Back to Main Menu"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) remote_ssh_manual ;;
            2) remote_ssh_from_list ;;
            3) change_ip ;;
            0) break ;;
            *) warn "Invalid option." ;;
        esac
    done
}

server_maintainer_menu() {
    while true; do
        echo
        echo "===== Server Maintainer ====="
        echo "1. Update package lists"
        echo "2. Upgrade packages"
        echo "3. Update & Upgrade"
        echo "4. Clean cache & clear memory"
        echo "5. Clean system logs"
        echo "6. Repair package management"
        echo "7. Check pending updates"
        echo "8. Check pending reboot"
        echo "0. Back to Main Menu"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) maintain_update ;;
            2) maintain_upgrade ;;
            3) maintain_update_upgrade ;;
            4) maintain_clean_cache_memory ;;
            5) maintain_clean_logs ;;
            6) maintain_repair_packages ;;
            7) maintain_pending_updates ;;
            8) maintain_check_reboot ;;
            0) break ;;
            *) warn "Invalid option." ;;
        esac
    done
}

server_information_menu() {
    while true; do
        echo
        echo "===== Server Information ====="
        echo "1. Info Server (Full System Monitor)"
        echo "2. Check partition disk (fdisk)"
        echo "3. Check disk structure (lsblk)"
        echo "4. Check UUID & filesystem type (blkid)"
        echo "0. Back to Main Menu"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) info_server ;;
            2) info_partition_disk ;;
            3) info_disk_structure ;;
            4) info_uuid_fstype ;;
            0) break ;;
            *) warn "Invalid option." ;;
        esac
    done
}

user_management_menu() {
    while true; do
        echo
        echo "===== User Management ====="
        echo "1. User List"
        echo "2. Add new user"
        echo "3. Delete user"
        echo "4. Change user password"
        echo "0. Back to Main Menu"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) user_list ;;
            2) user_add ;;
            3) user_delete ;;
            4) user_change_password ;;
            0) break ;;
            *) warn "Invalid option." ;;
        esac
    done
}

security_management_menu() {
    while true; do
        echo
        echo "===== Security Management ====="
        echo "1. Firewall status"
        echo "2. Firewall service (start/stop/restart)"
        echo "3. Firewall add rule (allow port / drop/reject IP)"
        echo "4. Virus scan (folder scan)"
        echo "5. Check failed logins"
        echo "6. Check open ports"
        echo "7. SSL Certificate Management (Let's Encrypt)"
        echo "0. Back to Main Menu"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) sec_firewall_status ;;
            2) sec_firewall_service ;;
            3) sec_firewall_add_rule ;;
            4) sec_virus_scan ;;
            5) sec_failed_logins ;;
            6) sec_open_ports ;;
            7) sec_ssl_menu ;;
            0) break ;;
            *) warn "Invalid option." ;;
        esac
    done
}

service_management_menu() {
    while true; do
        echo
        echo "===== Service Server Management ====="
        echo "1. Service status"
        echo "2. Service stop (stop running service)"
        echo "3. Service start (start stopped service)"
        echo "4. Service restart"
        echo "5. Auto service start (start if down)"
        echo "0. Back to Main Menu"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) service_status ;;
            2) service_stop ;;
            3) service_start ;;
            4) service_restart ;;
            5) service_auto_start ;;
            0) break ;;
            *) warn "Invalid option." ;;
        esac
    done
}

# ======================================================================
# Server Management (Tuning & Repair)
# ======================================================================

server_management_menu() {
    while true; do
        echo
        echo "===== Server Management ====="
        echo "1. Auto tuning webserver based on resource"
        echo "2. Auto tuning database based on resource"
        echo "3. Database repair / optimize"
        echo "0. Back to Main Menu"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) auto_tune_webserver ;;
            2) auto_tune_database ;;
            3) database_repair ;;
            0) break ;;
            *) warn "Invalid option." ;;
        esac
    done
}

auto_tune_webserver() {
    read_servers
    if ! select_servers; then return; fi
    read -p "Proceed with auto-tuning webserver on selected servers? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        info "Aborted."
        return
    fi

    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

# Detect CPU cores
CPU=$(nproc 2>/dev/null || echo 1)
# Detect total RAM in MB
MEM=$(free -m | awk '/Mem:/{print $2}')
[ -z "$MEM" ] && MEM=1024

# Detect webserver: nginx or apache
if command -v nginx >/dev/null 2>&1 && systemctl is-active nginx >/dev/null 2>&1; then
    echo "Detected Nginx. Tuning..."
    if [ -f /etc/nginx/nginx.conf ]; then
        $SUDO cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak.$(date +%Y%m%d%H%M%S)
        # worker_processes = CPU cores
        $SUDO sed -i "s/^worker_processes .*/worker_processes $CPU;/" /etc/nginx/nginx.conf
        # worker_connections = CPU * 1024 (adjust based on memory)
        CONN=$((CPU * 1024))
        $SUDO sed -i "s/^worker_connections .*/worker_connections $CONN;/" /etc/nginx/nginx.conf
        # Optional: increase client_max_body_size if not set
        if ! grep -q "client_max_body_size" /etc/nginx/nginx.conf; then
            $SUDO sed -i "/http {/a \    client_max_body_size 100M;" /etc/nginx/nginx.conf
        fi
        $SUDO systemctl restart nginx
        echo "Nginx tuned: worker_processes=$CPU, worker_connections=$CONN"
    else
        echo "nginx.conf not found at /etc/nginx/nginx.conf"
    fi
elif command -v apache2 >/dev/null 2>&1 && systemctl is-active apache2 >/dev/null 2>&1; then
    echo "Detected Apache2 (Debian/Ubuntu). Tuning..."
    CONF="/etc/apache2/apache2.conf"
    if [ -f "$CONF" ]; then
        $SUDO cp "$CONF" "$CONF.bak.$(date +%Y%m%d%H%M%S)"
        # Determine MPM: prefork or event/worker
        if grep -q "mpm_prefork" /etc/apache2/mods-enabled/*.conf 2>/dev/null; then
            # Prefork: set MaxRequestWorkers based on RAM (approx 2MB per worker)
            MAX_WORKERS=$(( MEM / 2 ))
            [ $MAX_WORKERS -lt 50 ] && MAX_WORKERS=50
            [ $MAX_WORKERS -gt 1000 ] && MAX_WORKERS=1000
            $SUDO sed -i "s/^[ ]*MaxRequestWorkers .*/MaxRequestWorkers $MAX_WORKERS/" /etc/apache2/mods-available/mpm_prefork.conf
            $SUDO sed -i "s/^[ ]*StartServers .*/StartServers $(( CPU * 2 ))/" /etc/apache2/mods-available/mpm_prefork.conf
            $SUDO sed -i "s/^[ ]*MinSpareServers .*/MinSpareServers $(( CPU * 2 ))/" /etc/apache2/mods-available/mpm_prefork.conf
            $SUDO sed -i "s/^[ ]*MaxSpareServers .*/MaxSpareServers $(( CPU * 4 ))/" /etc/apache2/mods-available/mpm_prefork.conf
            echo "Apache prefork tuned: MaxRequestWorkers=$MAX_WORKERS"
        else
            # event or worker: adjust threads/connections
            MAX_WORKERS=$(( MEM / 4 ))
            [ $MAX_WORKERS -lt 50 ] && MAX_WORKERS=50
            [ $MAX_WORKERS -gt 2000 ] && MAX_WORKERS=2000
            $SUDO sed -i "s/^[ ]*MaxRequestWorkers .*/MaxRequestWorkers $MAX_WORKERS/" /etc/apache2/mods-available/mpm_event.conf 2>/dev/null || \
            $SUDO sed -i "s/^[ ]*MaxRequestWorkers .*/MaxRequestWorkers $MAX_WORKERS/" /etc/apache2/mods-available/mpm_worker.conf 2>/dev/null
            echo "Apache event/worker tuned: MaxRequestWorkers=$MAX_WORKERS"
        fi
        $SUDO systemctl restart apache2
    else
        echo "Apache2 config not found at $CONF"
    fi
elif command -v httpd >/dev/null 2>&1 && systemctl is-active httpd >/dev/null 2>&1; then
    echo "Detected Apache (RHEL/CentOS). Tuning..."
    CONF="/etc/httpd/conf/httpd.conf"
    if [ -f "$CONF" ]; then
        $SUDO cp "$CONF" "$CONF.bak.$(date +%Y%m%d%H%M%S)"
        # Similar tuning for prefork or event
        MAX_WORKERS=$(( MEM / 2 ))
        [ $MAX_WORKERS -lt 50 ] && MAX_WORKERS=50
        [ $MAX_WORKERS -gt 1000 ] && MAX_WORKERS=1000
        $SUDO sed -i "s/^[ ]*MaxRequestWorkers .*/MaxRequestWorkers $MAX_WORKERS/" /etc/httpd/conf/httpd.conf
        $SUDO sed -i "s/^[ ]*StartServers .*/StartServers $(( CPU * 2 ))/" /etc/httpd/conf/httpd.conf
        $SUDO sed -i "s/^[ ]*MinSpareServers .*/MinSpareServers $(( CPU * 2 ))/" /etc/httpd/conf/httpd.conf
        $SUDO sed -i "s/^[ ]*MaxSpareServers .*/MaxSpareServers $(( CPU * 4 ))/" /etc/httpd/conf/httpd.conf
        $SUDO systemctl restart httpd
        echo "Apache (httpd) tuned: MaxRequestWorkers=$MAX_WORKERS"
    else
        echo "httpd.conf not found at $CONF"
    fi
else
    echo "No supported webserver (nginx/apache) found running."
fi
EOF
)
    run_action_on_servers_sudo "$script" "Auto-tune webserver"
}

auto_tune_database() {
    read_servers
    if ! select_servers; then return; fi
    read -p "Proceed with auto-tuning database on selected servers? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        info "Aborted."
        return
    fi

    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

# Detect database: MySQL/MariaDB or PostgreSQL
if command -v mysql >/dev/null 2>&1 && systemctl is-active mysql >/dev/null 2>&1; then
    DB="mysql"
elif command -v mariadb >/dev/null 2>&1 && systemctl is-active mariadb >/dev/null 2>&1; then
    DB="mariadb"
elif command -v postgres >/dev/null 2>&1 && systemctl is-active postgresql >/dev/null 2>&1; then
    DB="postgres"
else
    echo "No supported database (MySQL/MariaDB/PostgreSQL) found running."
    exit 1
fi

# Get total RAM in MB
MEM=$(free -m | awk '/Mem:/{print $2}')
[ -z "$MEM" ] && MEM=1024
# Calculate buffer pool size: 70% of RAM for dedicated, 50% for shared (adjust)
# We assume dedicated server; reduce if other services run.
BUFFER_SIZE=$(( MEM * 70 / 100 ))
[ $BUFFER_SIZE -lt 256 ] && BUFFER_SIZE=256
[ $BUFFER_SIZE -gt 8192 ] && BUFFER_SIZE=8192   # cap at 8GB to avoid over-allocation

case $DB in
    mysql|mariadb)
        CONF="/etc/mysql/my.cnf"
        [ ! -f "$CONF" ] && CONF="/etc/my.cnf"
        if [ -f "$CONF" ]; then
            $SUDO cp "$CONF" "$CONF.bak.$(date +%Y%m%d%H%M%S)"
            # Remove existing innodb_buffer_pool_size lines
            $SUDO sed -i '/^innodb_buffer_pool_size/d' "$CONF"
            $SUDO sed -i '/^query_cache_size/d' "$CONF"
            $SUDO sed -i '/^max_connections/d' "$CONF"
            # Add new settings under [mysqld] section (or create if missing)
            if grep -q "\[mysqld\]" "$CONF"; then
                $SUDO sed -i "/\[mysqld\]/a innodb_buffer_pool_size = ${BUFFER_SIZE}M\nquery_cache_size = ${BUFFER_SIZE}M\nmax_connections = $(( MEM / 2 ))" "$CONF"
            else
                echo -e "\n[mysqld]\ninnodb_buffer_pool_size = ${BUFFER_SIZE}M\nquery_cache_size = ${BUFFER_SIZE}M\nmax_connections = $(( MEM / 2 ))" | $SUDO tee -a "$CONF"
            fi
            $SUDO systemctl restart mysql || $SUDO systemctl restart mariadb
            echo "MySQL/MariaDB tuned: innodb_buffer_pool_size=${BUFFER_SIZE}M, max_connections=$(( MEM / 2 ))"
        else
            echo "MySQL config file not found."
        fi
        ;;
    postgres)
        CONF="/etc/postgresql/*/main/postgresql.conf"  # version specific
        # Simplify: find latest version
        CONF=$(ls /etc/postgresql/*/main/postgresql.conf 2>/dev/null | head -1)
        if [ -f "$CONF" ]; then
            $SUDO cp "$CONF" "$CONF.bak.$(date +%Y%m%d%H%M%S)"
            # Set shared_buffers to 25% of RAM (PostgreSQL recommendation)
            SHARED=$(( MEM * 25 / 100 ))
            [ $SHARED -lt 128 ] && SHARED=128
            [ $SHARED -gt 8192 ] && SHARED=8192
            $SUDO sed -i "s/^shared_buffers = .*/shared_buffers = ${SHARED}MB/" "$CONF"
            $SUDO sed -i "s/^max_connections = .*/max_connections = $(( MEM / 4 ))/" "$CONF"
            $SUDO systemctl restart postgresql
            echo "PostgreSQL tuned: shared_buffers=${SHARED}MB, max_connections=$(( MEM / 4 ))"
        else
            echo "PostgreSQL config not found."
        fi
        ;;
esac
EOF
)
    run_action_on_servers_sudo "$script" "Auto-tune database"
}

database_repair() {
    read_servers
    if ! select_servers; then return; fi
    echo "Select database repair action:"
    echo "1) Optimize tables (mysqlcheck -o)"
    echo "2) Repair tables (mysqlcheck -r)"
    echo "3) Optimize and repair (mysqlcheck -o -r)"
    read -p "Choose (1-3): " action
    case $action in
        1) repair_opt="--optimize" ;;
        2) repair_opt="--repair" ;;
        3) repair_opt="--optimize --repair" ;;
        *) warn "Invalid choice."; return ;;
    esac

    read -p "Proceed with database repair/optimize on selected servers? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        info "Aborted."
        return
    fi

    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

# Detect MySQL/MariaDB and run mysqlcheck
if command -v mysql >/dev/null 2>&1; then
    DB="mysql"
elif command -v mariadb >/dev/null 2>&1; then
    DB="mariadb"
else
    echo "MySQL/MariaDB not found."
    exit 1
fi

# Get mysql credentials (assume root with no password or from /root/.my.cnf)
# Try to use debian-sys-maint if available
if [ -f /etc/mysql/debian.cnf ]; then
    USER=$(grep "^user" /etc/mysql/debian.cnf | head -1 | awk '{print $3}')
    PASS=$(grep "^password" /etc/mysql/debian.cnf | head -1 | awk '{print $3}')
    HOST="localhost"
elif [ -f /root/.my.cnf ]; then
    USER=$(grep "^user" /root/.my.cnf | head -1 | awk '{print $3}')
    PASS=$(grep "^password" /root/.my.cnf | head -1 | awk '{print $3}')
    HOST=$(grep "^host" /root/.my.cnf | head -1 | awk '{print $3}')
    [ -z "$HOST" ] && HOST="localhost"
else
    # Fallback: try root without password
    USER="root"
    PASS=""
    HOST="localhost"
fi

if [ -z "$USER" ]; then
    USER="root"
fi

MYSQL_CMD="mysql -h $HOST -u $USER"
[ -n "$PASS" ] && MYSQL_CMD="$MYSQL_CMD -p$PASS"

# Check if we can connect
if ! $MYSQL_CMD -e "exit" 2>/dev/null; then
    echo "Cannot connect to MySQL/MariaDB. Skipping."
    exit 1
fi

echo "Running mysqlcheck $repair_opt --all-databases ..."
$SUDO mysqlcheck $repair_opt --all-databases -h $HOST -u $USER $([ -n "$PASS" ] && echo "-p$PASS") 2>&1
if [ $? -eq 0 ]; then
    echo "Database repair/optimize completed successfully."
else
    echo "mysqlcheck completed with warnings/errors (check output)."
fi
EOF
)
    script=$(echo "$script" | sed "s/\\\$repair_opt/$repair_opt/g")
    run_action_on_servers_sudo "$script" "Database repair/optimize"
}


# ======================================================================
# 11. Server Installation Management
# ======================================================================

run_install_script() {
    local script="$1"
    local desc="$2"
    run_action_on_servers_sudo "$script" "$desc"
}

# ----------------------------------------------------------------------
# Instalasi Komponen Tunggal
# ----------------------------------------------------------------------
install_apache_php() {
    echo "Akan menginstal: Apache2 + PHP (mod_php) + ekstensi umum."
    echo "Paket: apache2, php, libapache2-mod-php, php-mysql, php-pgsql, php-cli, php-curl, php-zip, php-gd, php-mbstring, php-xml"
    if ! confirm_action "Lanjutkan instalasi?"; then
        info "Instalasi dibatalkan."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
if [ -f /etc/debian_version ]; then
    $SUDO apt-get update
    $SUDO apt-get install -y apache2 php libapache2-mod-php php-mysql php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    $SUDO systemctl enable apache2
    $SUDO systemctl start apache2
    echo "Apache status:"
    $SUDO systemctl status apache2 --no-pager | head -5
elif [ -f /etc/redhat-release ]; then
    $SUDO yum install -y httpd php php-mysqlnd php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    $SUDO systemctl enable httpd
    $SUDO systemctl start httpd
    echo "Apache status:"
    $SUDO systemctl status httpd --no-pager | head -5
else
    echo "Unsupported OS"
    exit 1
fi
php -v | head -1
echo "Apache + PHP installed successfully."
EOF
)
    run_install_script "$script" "Install Apache + PHP"
    echo "========================================="
    echo "Instalasi selesai. File konfigurasi:"
    echo "  Apache: /etc/apache2/apache2.conf (Debian/Ubuntu) atau /etc/httpd/conf/httpd.conf (RHEL)"
    echo "  PHP: /etc/php/*/cli/php.ini dan /etc/php/*/apache2/php.ini"
    echo "  VirtualHost: /etc/apache2/sites-available/ (Debian) atau /etc/httpd/conf.d/ (RHEL)"
    echo "Untuk mengedit manual: nano /path/file"
    echo "Restart service setelah perubahan: systemctl restart apache2 (atau httpd)"
}

install_nginx_php() {
    echo "Akan menginstal: Nginx + PHP-FPM + ekstensi PHP."
    echo "Paket: nginx, php-fpm, php-mysql, php-pgsql, php-cli, php-curl, php-zip, php-gd, php-mbstring, php-xml"
    if ! confirm_action "Lanjutkan instalasi?"; then
        info "Instalasi dibatalkan."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
if [ -f /etc/debian_version ]; then
    $SUDO apt-get update
    $SUDO apt-get install -y nginx php-fpm php-mysql php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    $SUDO systemctl enable nginx php-fpm
    $SUDO systemctl start nginx php-fpm
    echo "Nginx status:"
    $SUDO systemctl status nginx --no-pager | head -5
    echo "PHP-FPM status:"
    $SUDO systemctl status php-fpm --no-pager | head -5
elif [ -f /etc/redhat-release ]; then
    $SUDO yum install -y epel-release
    $SUDO yum install -y nginx php-fpm php-mysqlnd php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    $SUDO systemctl enable nginx php-fpm
    $SUDO systemctl start nginx php-fpm
    echo "Nginx status:"
    $SUDO systemctl status nginx --no-pager | head -5
    echo "PHP-FPM status:"
    $SUDO systemctl status php-fpm --no-pager | head -5
else
    echo "Unsupported OS"
    exit 1
fi
php -v | head -1
echo "Nginx + PHP-FPM installed successfully."
EOF
)
    run_install_script "$script" "Install Nginx + PHP"
    echo "========================================="
    echo "File konfigurasi:"
    echo "  Nginx: /etc/nginx/nginx.conf"
    echo "  PHP-FPM: /etc/php/*/fpm/php.ini dan /etc/php/*/fpm/pool.d/www.conf"
    echo "  VirtualHost: /etc/nginx/sites-available/ (Debian) atau /etc/nginx/conf.d/ (RHEL)"
    echo "Restart service setelah perubahan: systemctl restart nginx php-fpm"
}

install_mariadb() {
    echo "Akan menginstal: MariaDB Server + Client."
    if ! confirm_action "Lanjutkan instalasi?"; then
        info "Instalasi dibatalkan."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
if [ -f /etc/debian_version ]; then
    $SUDO apt-get update
    $SUDO apt-get install -y mariadb-server mariadb-client
    $SUDO systemctl enable mariadb
    $SUDO systemctl start mariadb
elif [ -f /etc/redhat-release ]; then
    $SUDO yum install -y mariadb-server mariadb
    $SUDO systemctl enable mariadb
    $SUDO systemctl start mariadb
else
    echo "Unsupported OS"
    exit 1
fi
$SUDO systemctl status mariadb --no-pager | head -5
mysql --version
echo "MariaDB installed and started."
EOF
)
    run_install_script "$script" "Install MariaDB"
    echo "========================================="
    echo "File konfigurasi: /etc/mysql/my.cnf (Debian) atau /etc/my.cnf (RHEL)"
    echo "Setelah instalasi, jalankan 'mysql_secure_installation' untuk keamanan."
    echo "Untuk mengedit: nano /etc/mysql/my.cnf"
    echo "Restart: systemctl restart mariadb"
}

install_postgresql() {
    echo "Akan menginstal: PostgreSQL Server + kontribusi."
    if ! confirm_action "Lanjutkan instalasi?"; then
        info "Instalasi dibatalkan."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
if [ -f /etc/debian_version ]; then
    $SUDO apt-get update
    $SUDO apt-get install -y postgresql postgresql-contrib
    $SUDO systemctl enable postgresql
    $SUDO systemctl start postgresql
elif [ -f /etc/redhat-release ]; then
    $SUDO yum install -y postgresql-server postgresql-contrib
    $SUDO postgresql-setup initdb
    $SUDO systemctl enable postgresql
    $SUDO systemctl start postgresql
else
    echo "Unsupported OS"
    exit 1
fi
$SUDO systemctl status postgresql --no-pager | head -5
psql --version
echo "PostgreSQL installed and started."
EOF
)
    run_install_script "$script" "Install PostgreSQL"
    echo "========================================="
    echo "File konfigurasi: /etc/postgresql/*/main/postgresql.conf (Debian) atau /var/lib/pgsql/data/postgresql.conf (RHEL)"
    echo "File hba: /etc/postgresql/*/main/pg_hba.conf"
    echo "Untuk mengedit: nano /path/postgresql.conf"
    echo "Restart: systemctl restart postgresql"
}

# ----------------------------------------------------------------------
# Stack Lengkap
# ----------------------------------------------------------------------
install_lamp() {
    echo "Akan menginstal LAMP (Apache + PHP + MariaDB) secara bersamaan."
    if ! confirm_action "Lanjutkan?"; then
        info "Instalasi dibatalkan."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
if [ -f /etc/debian_version ]; then
    $SUDO apt-get update
    $SUDO apt-get install -y apache2 php libapache2-mod-php php-mysql php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    $SUDO systemctl enable apache2
    $SUDO systemctl start apache2
    $SUDO apt-get install -y mariadb-server mariadb-client
    $SUDO systemctl enable mariadb
    $SUDO systemctl start mariadb
elif [ -f /etc/redhat-release ]; then
    $SUDO yum install -y httpd php php-mysqlnd php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    $SUDO systemctl enable httpd
    $SUDO systemctl start httpd
    $SUDO yum install -y mariadb-server mariadb
    $SUDO systemctl enable mariadb
    $SUDO systemctl start mariadb
else
    echo "Unsupported OS"
    exit 1
fi
echo "Services status:"
$SUDO systemctl status apache2 --no-pager | head -3 2>/dev/null || $SUDO systemctl status httpd --no-pager | head -3
$SUDO systemctl status mariadb --no-pager | head -3
echo "LAMP installed successfully."
EOF
)
    run_install_script "$script" "Install LAMP"
    echo "========================================="
    echo "File konfigurasi:"
    echo "  Apache: /etc/apache2/apache2.conf atau /etc/httpd/conf/httpd.conf"
    echo "  PHP: /etc/php/*/apache2/php.ini"
    echo "  MariaDB: /etc/mysql/my.cnf atau /etc/my.cnf"
    echo "Jangan lupa jalankan mysql_secure_installation."
}

install_lapp() {
    echo "Akan menginstal LAPP (Apache + PHP + PostgreSQL) secara bersamaan."
    if ! confirm_action "Lanjutkan?"; then
        info "Instalasi dibatalkan."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
if [ -f /etc/debian_version ]; then
    $SUDO apt-get update
    $SUDO apt-get install -y apache2 php libapache2-mod-php php-mysql php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    $SUDO systemctl enable apache2
    $SUDO systemctl start apache2
    $SUDO apt-get install -y postgresql postgresql-contrib
    $SUDO systemctl enable postgresql
    $SUDO systemctl start postgresql
elif [ -f /etc/redhat-release ]; then
    $SUDO yum install -y httpd php php-mysqlnd php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    $SUDO systemctl enable httpd
    $SUDO systemctl start httpd
    $SUDO yum install -y postgresql-server postgresql-contrib
    $SUDO postgresql-setup initdb
    $SUDO systemctl enable postgresql
    $SUDO systemctl start postgresql
else
    echo "Unsupported OS"
    exit 1
fi
echo "Services status:"
$SUDO systemctl status apache2 --no-pager | head -3 2>/dev/null || $SUDO systemctl status httpd --no-pager | head -3
$SUDO systemctl status postgresql --no-pager | head -3
echo "LAPP installed successfully."
EOF
)
    run_install_script "$script" "Install LAPP"
    echo "========================================="
    echo "File konfigurasi:"
    echo "  Apache: /etc/apache2/apache2.conf atau /etc/httpd/conf/httpd.conf"
    echo "  PHP: /etc/php/*/apache2/php.ini"
    echo "  PostgreSQL: /etc/postgresql/*/main/postgresql.conf atau /var/lib/pgsql/data/postgresql.conf"
}

install_lemp() {
    echo "Akan menginstal LEMP (Nginx + PHP-FPM + MariaDB) secara bersamaan."
    if ! confirm_action "Lanjutkan?"; then
        info "Instalasi dibatalkan."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
if [ -f /etc/debian_version ]; then
    $SUDO apt-get update
    $SUDO apt-get install -y nginx php-fpm php-mysql php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    $SUDO systemctl enable nginx php-fpm
    $SUDO systemctl start nginx php-fpm
    $SUDO apt-get install -y mariadb-server mariadb-client
    $SUDO systemctl enable mariadb
    $SUDO systemctl start mariadb
elif [ -f /etc/redhat-release ]; then
    $SUDO yum install -y epel-release
    $SUDO yum install -y nginx php-fpm php-mysqlnd php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    $SUDO systemctl enable nginx php-fpm
    $SUDO systemctl start nginx php-fpm
    $SUDO yum install -y mariadb-server mariadb
    $SUDO systemctl enable mariadb
    $SUDO systemctl start mariadb
else
    echo "Unsupported OS"
    exit 1
fi
echo "Services status:"
$SUDO systemctl status nginx --no-pager | head -3
$SUDO systemctl status php-fpm --no-pager | head -3 2>/dev/null
$SUDO systemctl status mariadb --no-pager | head -3
echo "LEMP installed successfully."
EOF
)
    run_install_script "$script" "Install LEMP"
    echo "========================================="
    echo "File konfigurasi:"
    echo "  Nginx: /etc/nginx/nginx.conf"
    echo "  PHP-FPM: /etc/php/*/fpm/php.ini"
    echo "  MariaDB: /etc/mysql/my.cnf atau /etc/my.cnf"
}

install_lepp() {
    echo "Akan menginstal LEPP (Nginx + PHP-FPM + PostgreSQL) secara bersamaan."
    if ! confirm_action "Lanjutkan?"; then
        info "Instalasi dibatalkan."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
if [ -f /etc/debian_version ]; then
    $SUDO apt-get update
    $SUDO apt-get install -y nginx php-fpm php-mysql php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    $SUDO systemctl enable nginx php-fpm
    $SUDO systemctl start nginx php-fpm
    $SUDO apt-get install -y postgresql postgresql-contrib
    $SUDO systemctl enable postgresql
    $SUDO systemctl start postgresql
elif [ -f /etc/redhat-release ]; then
    $SUDO yum install -y epel-release
    $SUDO yum install -y nginx php-fpm php-mysqlnd php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    $SUDO systemctl enable nginx php-fpm
    $SUDO systemctl start nginx php-fpm
    $SUDO yum install -y postgresql-server postgresql-contrib
    $SUDO postgresql-setup initdb
    $SUDO systemctl enable postgresql
    $SUDO systemctl start postgresql
else
    echo "Unsupported OS"
    exit 1
fi
echo "Services status:"
$SUDO systemctl status nginx --no-pager | head -3
$SUDO systemctl status php-fpm --no-pager | head -3 2>/dev/null
$SUDO systemctl status postgresql --no-pager | head -3
echo "LEPP installed successfully."
EOF
)
    run_install_script "$script" "Install LEPP"
    echo "========================================="
    echo "File konfigurasi:"
    echo "  Nginx: /etc/nginx/nginx.conf"
    echo "  PHP-FPM: /etc/php/*/fpm/php.ini"
    echo "  PostgreSQL: /etc/postgresql/*/main/postgresql.conf atau /var/lib/pgsql/data/postgresql.conf"
}

# ----------------------------------------------------------------------
# Auto Tuning
# ----------------------------------------------------------------------
auto_tune_apache() {
    echo "Akan melakukan auto-tuning Apache berdasarkan resource server (RAM & CPU)."
    echo "Perubahan akan diterapkan pada konfigurasi MPM prefork."
    if ! confirm_action "Lanjutkan tuning?"; then
        info "Tuning dibatalkan."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

mem_total=$(free -m | awk '/^Mem:/{print $2}')
cpu_cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)
if [ -f /etc/apache2/apache2.conf ] || [ -f /etc/httpd/conf/httpd.conf ]; then
    if [ -f /etc/apache2/apache2.conf ]; then
        CONF="/etc/apache2/apache2.conf"
        MODS_DIR="/etc/apache2/mods-available"
    else
        CONF="/etc/httpd/conf/httpd.conf"
        MODS_DIR="/etc/httpd/conf.modules.d"
    fi
    if [ -f /etc/apache2/mods-available/mpm_prefork.conf ]; then
        a2enmod mpm_prefork 2>/dev/null
    fi
    max_workers=$(( (mem_total * 80 / 100) / 15 ))
    [ $max_workers -lt 5 ] && max_workers=5
    max_workers=$(( max_workers < (cpu_cores * 20) ? max_workers : cpu_cores * 20 ))
    start_servers=$(( cpu_cores * 2 ))
    [ $start_servers -lt 3 ] && start_servers=3
    min_spare=$(( cpu_cores * 2 ))
    max_spare=$(( cpu_cores * 4 ))
    [ $max_spare -lt 5 ] && max_spare=5
    cat <<EOT > /tmp/apache_tuning.conf
<IfModule mpm_prefork_module>
    StartServers          $start_servers
    MinSpareServers       $min_spare
    MaxSpareServers       $max_spare
    MaxRequestWorkers     $max_workers
    MaxConnectionsPerChild 10000
</IfModule>
EOT
    if [ -f /etc/apache2/mods-available/mpm_prefork.conf ]; then
        $SUDO cp /tmp/apache_tuning.conf /etc/apache2/mods-available/mpm_prefork.conf
        $SUDO systemctl restart apache2
    elif [ -f /etc/httpd/conf.modules.d/mpm_prefork.conf ]; then
        $SUDO cp /tmp/apache_tuning.conf /etc/httpd/conf.modules.d/mpm_prefork.conf
        $SUDO systemctl restart httpd
    else
        $SUDO cat /tmp/apache_tuning.conf >> $CONF
        $SUDO systemctl restart apache2 2>/dev/null || $SUDO systemctl restart httpd
    fi
    echo "Apache tuning applied. Values: StartServers=$start_servers, MaxWorkers=$max_workers, MinSpare=$min_spare, MaxSpare=$max_spare"
else
    echo "Apache not found."
fi
EOF
)
    run_install_script "$script" "Auto Tuning Apache"
    echo "========================================="
    echo "Tuning selesai. File konfigurasi yang diubah:"
    echo "  - /etc/apache2/mods-available/mpm_prefork.conf (Debian)"
    echo "  - /etc/httpd/conf.modules.d/mpm_prefork.conf (RHEL) atau /etc/httpd/conf/httpd.conf"
    echo "Periksa nilai yang diterapkan di file tersebut."
    echo "Restart Apache untuk menerapkan: systemctl restart apache2 (atau httpd)"
}

auto_tune_nginx() {
    echo "Akan melakukan auto-tuning Nginx berdasarkan resource server."
    if ! confirm_action "Lanjutkan tuning?"; then
        info "Tuning dibatalkan."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

mem_total=$(free -m | awk '/^Mem:/{print $2}')
cpu_cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)
if [ -f /etc/nginx/nginx.conf ]; then
    worker_proc=$cpu_cores
    [ $worker_proc -lt 1 ] && worker_proc=1
    max_conn=$(( (mem_total * 1024) / 512 ))
    [ $max_conn -lt 1024 ] && max_conn=1024
    [ $max_conn -gt 65536 ] && max_conn=65536
    $SUDO sed -i "s/^worker_processes.*/worker_processes $worker_proc;/" /etc/nginx/nginx.conf
    $SUDO sed -i "s/^worker_connections.*/worker_connections $max_conn;/" /etc/nginx/nginx.conf
    echo "fs.file-max = 65535" | $SUDO tee -a /etc/sysctl.conf
    $SUDO sysctl -p
    $SUDO systemctl restart nginx
    echo "Nginx tuned: worker_processes=$worker_proc, worker_connections=$max_conn"
else
    echo "Nginx not found."
fi
EOF
)
    run_install_script "$script" "Auto Tuning Nginx"
    echo "========================================="
    echo "Tuning selesai. File yang diubah: /etc/nginx/nginx.conf"
    echo "Periksa nilai worker_processes dan worker_connections."
    echo "Restart Nginx: systemctl restart nginx"
}

auto_tune_db() {
    echo "Akan melakukan auto-tuning database (MariaDB/PostgreSQL) berdasarkan resource."
    if ! confirm_action "Lanjutkan tuning?"; then
        info "Tuning dibatalkan."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

mem_total=$(free -m | awk '/^Mem:/{print $2}')
cpu_cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)
if command -v mysql >/dev/null 2>&1 || command -v mariadb >/dev/null 2>&1; then
    innodb_pool=$(( mem_total * 70 / 100 ))
    [ $innodb_pool -lt 128 ] && innodb_pool=128
    if [ -f /etc/mysql/my.cnf ]; then
        $SUDO sed -i "s/^innodb_buffer_pool_size.*/innodb_buffer_pool_size = ${innodb_pool}M/" /etc/mysql/my.cnf
        grep -q "innodb_log_file_size" /etc/mysql/my.cnf || echo "innodb_log_file_size = 256M" | $SUDO tee -a /etc/mysql/my.cnf
        grep -q "max_connections" /etc/mysql/my.cnf || echo "max_connections = 200" | $SUDO tee -a /etc/mysql/my.cnf
        $SUDO systemctl restart mariadb || $SUDO systemctl restart mysql
        echo "MariaDB/MySQL tuned: innodb_buffer_pool_size=${innodb_pool}M"
    elif [ -f /etc/my.cnf ]; then
        $SUDO sed -i "s/^innodb_buffer_pool_size.*/innodb_buffer_pool_size = ${innodb_pool}M/" /etc/my.cnf
        grep -q "innodb_log_file_size" /etc/my.cnf || echo "innodb_log_file_size = 256M" | $SUDO tee -a /etc/my.cnf
        grep -q "max_connections" /etc/my.cnf || echo "max_connections = 200" | $SUDO tee -a /etc/my.cnf
        $SUDO systemctl restart mariadb || $SUDO systemctl restart mysql
        echo "MariaDB/MySQL tuned: innodb_buffer_pool_size=${innodb_pool}M"
    else
        echo "MySQL config not found."
    fi
elif command -v psql >/dev/null 2>&1; then
    shared_buf=$(( mem_total * 25 / 100 ))
    [ $shared_buf -lt 128 ] && shared_buf=128
    eff_cache=$(( mem_total * 50 / 100 ))
    work_mem=$(( (mem_total * 25 / 100) / 100 ))
    [ $work_mem -lt 4 ] && work_mem=4
    if [ -f /etc/postgresql/*/main/postgresql.conf ]; then
        CONF=$(ls /etc/postgresql/*/main/postgresql.conf | head -1)
    elif [ -f /var/lib/pgsql/data/postgresql.conf ]; then
        CONF=/var/lib/pgsql/data/postgresql.conf
    else
        echo "PostgreSQL config not found."
        exit 1
    fi
    $SUDO sed -i "s/^shared_buffers.*/shared_buffers = ${shared_buf}MB/" $CONF
    $SUDO sed -i "s/^effective_cache_size.*/effective_cache_size = ${eff_cache}MB/" $CONF
    $SUDO sed -i "s/^work_mem.*/work_mem = ${work_mem}MB/" $CONF
    $SUDO systemctl restart postgresql
    echo "PostgreSQL tuned: shared_buffers=${shared_buf}MB, work_mem=${work_mem}MB"
else
    echo "No database found."
fi
EOF
)
    run_install_script "$script" "Auto Tuning Database"
    echo "========================================="
    echo "Tuning selesai. File yang diubah:"
    echo "  MariaDB: /etc/mysql/my.cnf atau /etc/my.cnf"
    echo "  PostgreSQL: /etc/postgresql/*/main/postgresql.conf atau /var/lib/pgsql/data/postgresql.conf"
    echo "Restart service database setelah perubahan."
}

# ----------------------------------------------------------------------
# Rekomendasi Terbaik
# ----------------------------------------------------------------------
show_recommendations() {
    echo "Menampilkan rekomendasi terbaik untuk server web & database."
    if ! confirm_action "Lanjutkan?"; then
        info "Dibatalkan."
        return
    fi
    local script=$(cat <<'EOF'
#!/bin/bash
# Deteksi sudo (tidak diperlukan untuk rekomendasi, tapi konsisten)
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

mem_total=$(free -m | awk '/^Mem:/{print $2}')
cpu_cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)
echo "========== BEST PRACTICE RECOMMENDATIONS =========="
echo "Server specs: Memory=${mem_total}MB, CPU cores=$cpu_cores"
echo ""
echo "1. For Web Server (Apache/Nginx):"
echo "   - Use PHP-FPM instead of mod_php (Apache) for better performance."
echo "   - Enable opcache and set recommended values:"
echo "       opcache.memory_consumption=128"
echo "       opcache.max_accelerated_files=4000"
echo "   - For high traffic, use Nginx as reverse proxy + Apache/php-fpm."
echo "   - Enable Gzip compression and caching headers."
echo ""
echo "2. For Database (MySQL/MariaDB):"
echo "   - innodb_buffer_pool_size: 70-80% of RAM for dedicated DB."
echo "   - innodb_log_file_size: 256MB-1GB depending on writes."
echo "   - max_connections: adjust based on traffic; start with 200."
echo "   - Query cache: disable for high-write workloads."
echo ""
echo "3. For PostgreSQL:"
echo "   - shared_buffers: 25% of RAM."
echo "   - effective_cache_size: 50% of RAM."
echo "   - work_mem: (RAM * 0.25) / max_connections."
echo "   - Enable autovacuum and tune thresholds."
echo ""
echo "4. System-level:"
echo "   - Increase file descriptor limits (fs.file-max)."
echo "   - Use TCP tweaks: net.ipv4.tcp_tw_reuse, net.ipv4.tcp_fin_timeout."
echo "   - Keep OS updated and use a firewall."
echo ""
echo "5. Monitoring:"
echo "   - Install monitoring tools (htop, iotop, netstat)."
echo "   - Set up log rotation to avoid disk full."
echo ""
echo "Based on your current resources, consider:"
if [ $mem_total -lt 2048 ]; then
    echo "   - Low memory (<2GB): Use Nginx + PHP-FPM with small child limits."
    echo "   - Use MariaDB with small buffer pool."
elif [ $mem_total -lt 4096 ]; then
    echo "   - Medium memory (2-4GB): Apache + PHP-FPM or Nginx."
    echo "   - Database buffer pool: 1-2GB."
else
    echo "   - High memory (>4GB): Tune aggressively, use caching (Redis/Memcached)."
fi
echo "===================================================="
EOF
)
    run_install_script "$script" "Best Recommendations"
    echo "========================================="
    echo "Untuk mengimplementasikan rekomendasi, edit file konfigurasi:"
    echo "  - Apache: /etc/apache2/apache2.conf atau /etc/httpd/conf/httpd.conf"
    echo "  - Nginx: /etc/nginx/nginx.conf"
    echo "  - PHP: /etc/php/*/cli/php.ini dan /etc/php/*/fpm/php.ini (jika pakai FPM)"
    echo "  - MariaDB: /etc/mysql/my.cnf atau /etc/my.cnf"
    echo "  - PostgreSQL: /etc/postgresql/*/main/postgresql.conf atau /var/lib/pgsql/data/postgresql.conf"
    echo "Setelah mengedit, restart service terkait."
}

# ----------------------------------------------------------------------
# Instalasi Farm Server (Load Balancer/HA)
# ----------------------------------------------------------------------
install_farm_server() {
    echo "========================================="
    echo "  INSTALASI FARM SERVER (LOAD BALANCER/HA)"
    echo "========================================="
    echo "Arsitektur yang akan dibuat:"
    echo "  - 1 Load Balancer (HAProxy) - IP publik"
    echo "  - 2 Web Server (Nginx + PHP-FPM) - IP internal"
    echo "  - 1 Database Server (MariaDB atau PostgreSQL) - IP internal"
    echo "  - 1 File Server (NFS) - IP internal"
    echo ""
    echo "Pastikan semua server sudah memiliki SSH key dan akses sudo."
    if ! confirm_action "Lanjutkan instalasi farm server?"; then
        info "Dibatalkan."
        return
    fi

    # Kumpulkan IP
    echo "Masukkan alamat IP untuk masing-masing server (format: user@ip atau ip saja):"
    read -p "Load Balancer (HAProxy)   : " lb_ip
    read -p "Web Server 1              : " web1_ip
    read -p "Web Server 2              : " web2_ip
    read -p "Database Server           : " db_ip
    read -p "File Server (NFS)         : " fs_ip

    # Validasi sederhana
    if [[ -z "$lb_ip" || -z "$web1_ip" || -z "$web2_ip" || -z "$db_ip" || -z "$fs_ip" ]]; then
        error "Semua IP harus diisi."
        return
    fi

    # Pilih jenis database
    echo "Pilih jenis database:"
    echo "1) MariaDB"
    echo "2) PostgreSQL"
    read -p "Pilihan (1/2): " db_choice
    case $db_choice in
        1) DB_TYPE="mariadb" ;;
        2) DB_TYPE="postgresql" ;;
        *) error "Pilihan tidak valid."; return ;;
    esac

    echo "========================================="
    echo "Ringkasan konfigurasi:"
    echo "  LB       : $lb_ip"
    echo "  Web1     : $web1_ip"
    echo "  Web2     : $web2_ip"
    echo "  DB       : $db_ip ($DB_TYPE)"
    echo "  File     : $fs_ip"
    if ! confirm_action "Apakah konfigurasi sudah benar?"; then
        info "Dibatalkan."
        return
    fi

    info "Memulai instalasi Farm Server..."

    # ------------------------------------------------------------------
    # 1. Install dan konfigurasi File Server (NFS)
    # ------------------------------------------------------------------
    info "Menginstal File Server di $fs_ip ..."
    local fs_script=$(cat <<EOF
#!/bin/bash
# Deteksi sudo
if [ "\$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
echo "Installing NFS server..."
if [ -f /etc/debian_version ]; then
    \$SUDO apt-get update
    \$SUDO apt-get install -y nfs-kernel-server
elif [ -f /etc/redhat-release ]; then
    \$SUDO yum install -y nfs-utils
    \$SUDO systemctl enable nfs-server
    \$SUDO systemctl start nfs-server
else
    echo "Unsupported OS"
    exit 1
fi
# Buat direktori share
mkdir -p /srv/nfs/shared
chown nobody:nogroup /srv/nfs/shared
chmod 755 /srv/nfs/shared
# Konfigurasi exports (untuk web1 dan web2)
cat <<EOT | \$SUDO tee /etc/exports
/srv/nfs/shared $web1_ip(rw,sync,no_subtree_check,no_root_squash)
/srv/nfs/shared $web2_ip(rw,sync,no_subtree_check,no_root_squash)
EOT
\$SUDO exportfs -a
\$SUDO systemctl restart nfs-server 2>/dev/null || \$SUDO systemctl restart nfs-kernel-server
echo "NFS server configured. Shared directory: /srv/nfs/shared"
EOF
)
    run_script_on_server "$fs_ip" "$fs_script"
    echo "File Server selesai."

    # ------------------------------------------------------------------
    # 2. Install Database Server
    # ------------------------------------------------------------------
    info "Menginstal Database Server di $db_ip ($DB_TYPE) ..."
    local db_script
    if [[ "$DB_TYPE" == "mariadb" ]]; then
        db_script=$(cat <<EOF
#!/bin/bash
# Deteksi sudo
if [ "\$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
if [ -f /etc/debian_version ]; then
    \$SUDO apt-get update
    \$SUDO apt-get install -y mariadb-server mariadb-client
    \$SUDO systemctl enable mariadb
    \$SUDO systemctl start mariadb
elif [ -f /etc/redhat-release ]; then
    \$SUDO yum install -y mariadb-server mariadb
    \$SUDO systemctl enable mariadb
    \$SUDO systemctl start mariadb
else
    echo "Unsupported OS"
    exit 1
fi
# Set root password dan secure (opsional, bisa diatur manual)
# Buat database dan user untuk aplikasi (contoh)
mysql -e "CREATE DATABASE IF NOT EXISTS appdb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS 'appuser'@'%' IDENTIFIED BY 'securepassword';"
mysql -e "GRANT ALL PRIVILEGES ON appdb.* TO 'appuser'@'%';"
mysql -e "FLUSH PRIVILEGES;"
# Ubah bind-address agar bisa diakses dari web server
\$SUDO sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf 2>/dev/null || \$SUDO sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' /etc/my.cnf
\$SUDO systemctl restart mariadb
echo "MariaDB installed and configured. Database: appdb, User: appuser"
EOF
)
    else
        db_script=$(cat <<EOF
#!/bin/bash
# Deteksi sudo
if [ "\$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
if [ -f /etc/debian_version ]; then
    \$SUDO apt-get update
    \$SUDO apt-get install -y postgresql postgresql-contrib
    \$SUDO systemctl enable postgresql
    \$SUDO systemctl start postgresql
elif [ -f /etc/redhat-release ]; then
    \$SUDO yum install -y postgresql-server postgresql-contrib
    \$SUDO postgresql-setup initdb
    \$SUDO systemctl enable postgresql
    \$SUDO systemctl start postgresql
else
    echo "Unsupported OS"
    exit 1
fi
# Ubah konfigurasi agar bisa diakses dari web server
\$SUDO sed -i "s/^#listen_addresses.*/listen_addresses = '*'/" /var/lib/pgsql/data/postgresql.conf 2>/dev/null || \$SUDO sed -i "s/^#listen_addresses.*/listen_addresses = '*'/" /etc/postgresql/*/main/postgresql.conf
# Tambahkan rule di pg_hba.conf untuk web server
echo "host    all             all             $web1_ip/32            md5" | \$SUDO tee -a /var/lib/pgsql/data/pg_hba.conf 2>/dev/null || echo "host    all             all             $web1_ip/32            md5" | \$SUDO tee -a /etc/postgresql/*/main/pg_hba.conf
echo "host    all             all             $web2_ip/32            md5" | \$SUDO tee -a /var/lib/pgsql/data/pg_hba.conf 2>/dev/null || echo "host    all             all             $web2_ip/32            md5" | \$SUDO tee -a /etc/postgresql/*/main/pg_hba.conf
\$SUDO systemctl restart postgresql
# Buat user dan database
sudo -u postgres psql -c "CREATE USER appuser WITH PASSWORD 'securepassword';"
sudo -u postgres psql -c "CREATE DATABASE appdb OWNER appuser;"
echo "PostgreSQL installed and configured. Database: appdb, User: appuser"
EOF
)
    fi
    run_script_on_server "$db_ip" "$db_script"
    echo "Database Server selesai."

    # ------------------------------------------------------------------
    # 3. Install Web Server 1 & 2 (Nginx + PHP-FPM) + mount NFS
    # ------------------------------------------------------------------
    for web_server in "$web1_ip" "$web2_ip"; do
        info "Menginstal Web Server di $web_server ..."
        local web_script=$(cat <<EOF
#!/bin/bash
# Deteksi sudo
if [ "\$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
# Install Nginx + PHP-FPM
if [ -f /etc/debian_version ]; then
    \$SUDO apt-get update
    \$SUDO apt-get install -y nginx php-fpm php-mysql php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    \$SUDO systemctl enable nginx php-fpm
    \$SUDO systemctl start nginx php-fpm
elif [ -f /etc/redhat-release ]; then
    \$SUDO yum install -y epel-release
    \$SUDO yum install -y nginx php-fpm php-mysqlnd php-pgsql php-cli php-curl php-zip php-gd php-mbstring php-xml
    \$SUDO systemctl enable nginx php-fpm
    \$SUDO systemctl start nginx php-fpm
else
    echo "Unsupported OS"
    exit 1
fi
# Mount NFS dari fileserver
mkdir -p /var/www/html
# Tambahkan ke fstab agar mount otomatis
echo "$fs_ip:/srv/nfs/shared /var/www/html nfs defaults 0 0" | \$SUDO tee -a /etc/fstab
\$SUDO mount -a
# Konfigurasi Nginx virtual host sederhana
cat <<EOT | \$SUDO tee /etc/nginx/sites-available/default 2>/dev/null || \$SUDO tee /etc/nginx/conf.d/default.conf
server {
    listen 80;
    server_name _;
    root /var/www/html;
    index index.php index.html;
    location / {
        try_files \$uri \$uri/ =404;
    }
    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php*-fpm.sock 2>/dev/null || fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOT
# Aktifkan site jika Debian/Ubuntu
if [ -f /etc/nginx/sites-available/default ]; then
    \$SUDO ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
fi
# Buat file test
echo "<?php phpinfo(); ?>" | \$SUDO tee /var/www/html/info.php
# Restart nginx
\$SUDO systemctl restart nginx
echo "Web server installed. NFS mounted at /var/www/html"
EOF
)
        run_script_on_server "$web_server" "$web_script"
        echo "Web Server $web_server selesai."
    done

    # ------------------------------------------------------------------
    # 4. Install Load Balancer (HAProxy)
    # ------------------------------------------------------------------
    info "Menginstal Load Balancer di $lb_ip ..."
    local lb_script=$(cat <<EOF
#!/bin/bash
# Deteksi sudo
if [ "\$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found and not root, commands may fail" >&2
        SUDO=""
    fi
fi

set -e
if [ -f /etc/debian_version ]; then
    \$SUDO apt-get update
    \$SUDO apt-get install -y haproxy
elif [ -f /etc/redhat-release ]; then
    \$SUDO yum install -y haproxy
else
    echo "Unsupported OS"
    exit 1
fi
# Konfigurasi HAProxy
cat <<EOT | \$SUDO tee /etc/haproxy/haproxy.cfg
global
    log /dev/log local0
    maxconn 4096
    user haproxy
    group haproxy

defaults
    log global
    mode http
    option httplog
    option dontlognull
    retries 3
    timeout connect 5000
    timeout client 50000
    timeout server 50000

frontend http-in
    bind *:80
    default_backend web_servers

backend web_servers
    balance roundrobin
    server web1 $web1_ip:80 check
    server web2 $web2_ip:80 check
EOT
\$SUDO systemctl enable haproxy
\$SUDO systemctl restart haproxy
echo "HAProxy installed and configured. Load balancing to $web1_ip and $web2_ip"
EOF
)
    run_script_on_server "$lb_ip" "$lb_script"
    echo "Load Balancer selesai."

    echo "========================================="
    echo "INSTALASI FARM SERVER SELESAI!"
    echo "Ringkasan:"
    echo "  - Load Balancer : $lb_ip (akses via http)"
    echo "  - Web Server 1  : $web1_ip"
    echo "  - Web Server 2  : $web2_ip"
    echo "  - Database      : $db_ip ($DB_TYPE)"
    echo "  - File Server   : $fs_ip (NFS share: /srv/nfs/shared)"
    echo ""
    echo "Langkah selanjutnya:"
    echo "  1. Upload aplikasi web ke /var/www/html di web server (melalui NFS)."
    echo "  2. Sesuaikan konfigurasi database di aplikasi (host=$db_ip, user=appuser, password=securepassword, db=appdb)."
    echo "  3. Uji akses melalui Load Balancer."
    echo "  4. Jangan lupa mengganti password default dan mengamankan konfigurasi."
}

instalasi_server_menu() {
    while true; do
        echo
        echo "===== Instalasi Server Management ====="
        echo "1. Install Web Server Apache + PHP"
        echo "2. Install Web Server Nginx + PHP"
        echo "3. Install Database MariaDB"
        echo "4. Install Database PostgreSQL"
        echo "5. Install Apache + PHP + MariaDB (LAMP)"
        echo "6. Install Apache + PHP + PostgreSQL (LAPP)"
        echo "7. Install Nginx + PHP + MariaDB (LEMP)"
        echo "8. Install Nginx + PHP + PostgreSQL (LEPP)"
        echo "9. Auto Tuning Apache2"
        echo "10. Auto Tuning Nginx"
        echo "11. Auto Tuning MariaDB/PostgreSQL"
        echo "12. Tampilkan Rekomendasi Terbaik"
        echo "13. Instalasi Farm Server (Load Balancer/HA)"
        echo "0. Kembali ke Menu Utama"
        echo -n "Pilih opsi: "
        read -r choice
        case $choice in
            1) install_apache_php ;;
            2) install_nginx_php ;;
            3) install_mariadb ;;
            4) install_postgresql ;;
            5) install_lamp ;;
            6) install_lapp ;;
            7) install_lemp ;;
            8) install_lepp ;;
            9) auto_tune_apache ;;
            10) auto_tune_nginx ;;
            11) auto_tune_db ;;
            12) show_recommendations ;;
            13) install_farm_server ;;
            0) break ;;
            *) warn "Pilihan tidak valid." ;;
        esac
    done
}

# ======================================================================
# Main Menu
# ======================================================================

main_menu() {
    while true; do
        echo
        echo "============ Main Menu  ============"
        echo "======== ManageServer V-3.3 ========"
        echo "1. SSH Key Management"
        echo "2. SSH Management"
        echo "3. Server Maintainer"
        echo "4. Server Information"
        echo "5. User Management"
        echo "6. Security Management"
        echo "7. Service Server Management"
        echo "8. Mailserver Management"
        echo "9. Network Tools"
        echo "10. APNIC Tools"
        echo "11. Server Management"
        echo "12. Instalasi Server Management"
        echo "13. Exit"
        echo -n "Choose an option: "
        read -r choice
        case $choice in
            1) ssh_key_management_menu ;;
            2) ssh_management_menu ;;
            3) server_maintainer_menu ;;
            4) server_information_menu ;;
            5) user_management_menu ;;
            6) security_management_menu ;;
            7) service_management_menu ;;
            8) mail_menu ;;
            9) network_tools_menu ;;
            10) apnic_tools_menu ;;
            11) server_management_menu ;;
            12) instalasi_server_menu ;;
            13) echo "Bye!"; exit 0 ;;
            *) warn "Invalid option." ;;
        esac
    done
}

# ----------------------------------------------------------------------
# Initialization
# ----------------------------------------------------------------------

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
ensure_base_packages || warn "Some packages missing."
read_servers

main_menu
