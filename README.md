Warkopv3.3.sh - Multi-Server Management Script

Copyright (C) 2026 sigithdteam-lab
GNU General Public License v3.0

📋 Overview

This is a comprehensive bash script for managing multiple Linux servers simultaneously. It functions as a centralized server management console that allows you to perform administrative tasks across many servers from a single machine.

---

🎯 Core Purpose

The script is designed for system administrators who need to manage fleets of Linux servers efficiently. It eliminates the need to manually SSH into each server for routine tasks by automating operations across multiple servers at once.

---

🔧 Key Features by Category

1. SSH Key Management

· Generate SSH key pairs locally
· Import/copy public keys to remote servers
· Test passwordless SSH connectivity
· Repair SSH permissions and known_hosts
· Remove keys from remote servers
· Regenerate keys

2. SSH Management

· Connect to servers manually or from list
· Add new servers to the list
· Change IP addresses on remote servers

3. Server Maintenance

· Update package lists
· Upgrade packages
· Clean system caches and memory
· Clean system logs (removes .gz files, truncates logs)
· Repair package management (dpkg/yum)
· Check pending updates
· Check if reboot is required

4. Server Information

· Full system monitor (CPU, memory, disk, network, processes)
· Partition disk information (fdisk)
· Disk structure (lsblk)
· UUID and filesystem type (blkid)

5. User Management

· List all users (human + system)
· Add new users with passwords
· Delete users (with home directory option)
· Change user passwords

6. Security Management

· Firewall status (UFW/firewalld)
· Start/stop/restart firewalls
· Add firewall rules (allow ports, drop/reject IPs)
· Virus scanning (ClamAV)
· Check failed login attempts
· Check open listening ports
· SSL Certificate Management (Let's Encrypt)
  · Install Certbot
  · Get new certificates
  · Renew certificates
  · Check expiry dates
  · List certificates
  · Setup auto-renewal cron job

7. Service Management

· View service status
· Stop/start/restart services
· Auto-start services if they go down

8. Mailserver Management

· Check MX records
· Check PTR (reverse DNS) records
· Generate/check DKIM keys
· Generate/check SPF records
· Generate/check DMARC records

9. Network Tools (Local)

· Ping subnet scan (nmap)
· Traceroute
· dig (DNS lookup)
· nslookup
· netstat (listening ports)
· MX check
· PTR check
· whois lookups

10. APNIC Tools (Local)

· Prefix Whois
· Route Object lookups
· ROA (RPKI) checks
· AS Number information
· RPKI Validation
· IPv6 Whois

11. Server Management

· Auto-tune web servers (Apache/Nginx) based on resources
· Auto-tune databases (MySQL/MariaDB/PostgreSQL)
· Database repair and optimization

12. Installation Management

· Install Apache + PHP
· Install Nginx + PHP
· Install MariaDB
· Install PostgreSQL
· Install LAMP (Apache + PHP + MariaDB)
· Install LAPP (Apache + PHP + PostgreSQL)
· Install LEMP (Nginx + PHP + MariaDB)
· Install LEPP (Nginx + PHP + PostgreSQL)
· Auto-tune Apache2
· Auto-tune Nginx
· Auto-tune databases
· Farm Server Installation (Load Balancer + multiple web servers + database + file server)

---

🚀 How to Use

Prerequisites

1. Bash shell (Linux/macOS) or WSL on Windows
2. SSH client installed
3. Passwordless sudo or ability to enter sudo passwords
4. Server list file (listserver.txt) in the same directory

Basic Usage

```bash
# Make script executable
chmod +x warkopv3.3.sh

# Run the script
./warkopv3.3.sh
```

Server List Format

Create listserver.txt with one server per line:

```
user@192.168.1.10:22
192.168.1.11:2222
user@server.example.com
```

Workflow Example

1. First time setup:
   · Generate SSH key (Menu 1 → Option 4)
   · Import key to servers (Menu 1 → Option 3)
   · Test passwordless connection (Menu 1 → Option 2)
2. Daily maintenance:
   · Select server list option
   · Choose which servers to target
   · Execute the desired operation

---

⚙️ How It Works

1. Server Selection & Caching

```bash
# Servers are cached for performance
read_servers()      # Loads servers into memory
select_servers()    # Interactive server selection with support for:
                    # - Single numbers: 1,2,3
                    # - Ranges: 1-5
                    # - "all" for all servers
```

2. SSH Connection Management

```bash
ssh_to_server()     # Establishes SSH connection with proper port/user
parse_server_string() # Parses "user@host:port" format
```

3. Remote Script Execution

The script sends bash scripts to remote servers using heredoc:

```bash
ssh user@host "bash -s" << 'EOF'
# Remote commands here
EOF
```

4. Sudo Detection

The script automatically detects if it's running as root:

```bash
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "WARNING: sudo not found"
        SUDO=""
    fi
fi
```

5. Parallel Execution

Optional parallel execution (disabled by default):

```bash
PARALLEL=true  # Set to enable parallel processing
```

6. OS Detection

The script detects OS family and uses appropriate commands:

· Debian/Ubuntu: apt-get, dpkg, systemctl
· RHEL/CentOS: yum, rpm, systemctl
· SUSE: zypper

7. Package Installation

Automatically detects package manager and installs missing packages:

· apt-get (Debian-based)
· yum (RHEL 6/7)
· dnf (RHEL 8+)
· zypper (SUSE)

---

📊 Key Data Flow

```
┌─────────────────┐
│  listserver.txt │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Read & Cache   │
│  Server List    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  User Selects   │
│  Servers        │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Execute Action │
│  (via SSH)      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Display        │
│  Results        │
└─────────────────┘
```

---

🛠️ Technical Highlights

Smart Features

1. Idempotent Operations: Many operations check if a package/service is already installed before acting
2. Error Handling: Graceful error handling with warnings instead of crashes
3. Progress Feedback: Color-coded output (INFO, WARN, ERROR)
4. Configurable: PARALLEL environment variable for performance
5. Cross-platform: Works on multiple Linux distributions

Security Considerations

· Uses SSH key authentication (no passwords stored in script)
· Sudo detection ensures proper privilege escalation
· Known_hosts management for security
· Firewall rules management

---

📝 Example Use Cases

Scenario 1: Deploy SSL Certificate to Multiple Servers

```bash
1. Run script
2. Choose Security Management (6)
3. Choose SSL Certificate Management (7)
4. Select "Get new certificate for domain"
5. Enter domain and email
6. Select target servers
7. Certificate installed on all selected servers
```

Scenario 2: Check System Health

```bash
1. Run script
2. Choose Server Information (4)
3. Choose Info Server (1)
4. Select target servers
5. Get comprehensive system report
```

Scenario 3: Bulk Package Update

```bash
1. Run script
2. Choose Server Maintainer (3)
3. Choose Update & Upgrade (3)
4. Select "all" servers
5. All servers update simultaneously
```

---

⚠️ Limitations & Considerations

1. Root Access: Some operations require sudo; ensure sudo permissions are configured
2. Network Latency: Operations depend on network speed to remote servers
3. Parallel Execution: Can overwhelm network if too many servers selected simultaneously
4. Package Manager Differences: Some packages have different names across distros
5. Firewall Detection: Only detects UFW and firewalld (not iptables directly)

---

🎨 Color Codes

The script uses color-coded output for readability:

· 🟡 Yellow: Information
· 🔴 Red: Errors
· 🟢 Green: Success
· 🔵 Blue: Menu options
· 🟣 Purple: Section headers

---

📄 Version Info

· Version: 3.3
· Date: July 2026
· Author: sigit hdteam-lab

---

🔄 Summary: Why Use This Script?

Without Script With Script
SSH to each server individually One command for all servers
Repeat operations manually Automated batch operations
Remember command syntax Menu-driven interface
No centralized management Centralized server list
Manual dependency checks Automatic dependency installation
Hard to audit Clear logging and output

This tool essentially transforms a server administrator's workflow from "SSH to each server and run commands" to "select servers from a list and click through a menu".
