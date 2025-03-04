#!/bin/bash
# Proxmox Firewall Configuration Script
# This script configures the Proxmox firewall with secure defaults

set -e  # Exit on any error

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

# Welcome message
log_info "Starting Proxmox firewall configuration"

# Ask for confirmation before proceeding
log_warn "This script will configure the Proxmox firewall."
log_warn "Make sure you have console access to the server in case of misconfiguration."
read -p "Do you want to continue? (y/n): " continue_setup
if [[ "$continue_setup" != "y" ]]; then
    log_info "Firewall configuration aborted."
    exit 0
fi

# Get network information
log_info "Gathering network information..."
read -p "Enter your management network CIDR (e.g., 192.168.1.0/24): " mgmt_network
mgmt_network=${mgmt_network:-"192.168.1.0/24"}

# Enable the firewall
log_info "Enabling Proxmox firewall..."

# Create firewall configuration directory if it doesn't exist
mkdir -p /etc/pve/firewall

# Configure datacenter level firewall
cat > /etc/pve/firewall/cluster.fw << EOF
[OPTIONS]
enable: 1
policy_in: DROP
policy_out: ACCEPT
log_level_in: nolog
log_level_out: nolog
tcp_flags_log_level: nolog
icmp_log_level: nolog
smurf_log_level: nolog

[RULES]
# Allow established and related connections
IN ACCEPT -m conntrack --ctstate ESTABLISHED,RELATED
# Allow ping
IN ACCEPT -p icmp
# Allow SSH from management network
IN ACCEPT -p tcp -s $mgmt_network --dport 22
# Allow Proxmox web interface from management network
IN ACCEPT -p tcp -s $mgmt_network --dport 8006
# Allow Proxmox VNC console from management network
IN ACCEPT -p tcp -s $mgmt_network --dport 5900:5999
# Allow Proxmox cluster communication
IN ACCEPT -p tcp --dport 3128
IN ACCEPT -p tcp --dport 5404:5405
IN ACCEPT -p udp --dport 5404:5405
IN ACCEPT -p tcp --dport 22
IN ACCEPT -p tcp --dport 111
IN ACCEPT -p udp --dport 111
IN ACCEPT -p tcp --dport 11211
IN ACCEPT -p tcp --dport 2049
IN ACCEPT -p udp --dport 2049
IN ACCEPT -p tcp --dport 32768:32769
IN ACCEPT -p udp --dport 32768:32769
EOF

# Configure node level firewall
cat > /etc/pve/nodes/$(hostname -s)/host.fw << EOF
[OPTIONS]
enable: 1
policy_in: DROP
policy_out: ACCEPT
log_level_in: nolog
log_level_out: nolog
tcp_flags_log_level: nolog
icmp_log_level: nolog
smurf_log_level: nolog

[RULES]
# Node-specific rules can be added here
EOF

# Configure VM/CT default firewall template
cat > /etc/pve/firewall/vm.fw << EOF
[OPTIONS]
enable: 1
policy_in: DROP
policy_out: ACCEPT
log_level_in: nolog
log_level_out: nolog
tcp_flags_log_level: nolog
icmp_log_level: nolog
smurf_log_level: nolog

[RULES]
# Allow established and related connections
IN ACCEPT -m conntrack --ctstate ESTABLISHED,RELATED
# Allow ping
IN ACCEPT -p icmp
# Allow SSH
IN ACCEPT -p tcp --dport 22
# Allow HTTP/HTTPS
IN ACCEPT -p tcp --dport 80
IN ACCEPT -p tcp --dport 443
EOF

# Apply firewall configuration
log_info "Applying firewall configuration..."
systemctl restart pve-firewall

# Create a script to check firewall status
log_info "Creating firewall status check script..."

cat > /usr/local/bin/check-firewall.sh << 'EOF'
#!/bin/bash
# Script to check Proxmox firewall status

# Set variables
LOG_FILE="/var/log/firewall-check.log"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Clear log file
> "$LOG_FILE"

# Start check
log_message "Starting Proxmox firewall status check"

# Check if firewall is enabled
if pve-firewall status | grep -q "active"; then
    log_message "✓ Firewall is active"
else
    log_message "✗ Firewall is NOT active"
fi

# Check firewall rules
log_message "Firewall rules:"
pve-firewall status | grep -A 100 "Rules:" | tee -a "$LOG_FILE"

# Check current connections
log_message "Current connections:"
pve-firewall log | tail -n 20 | tee -a "$LOG_FILE"

# Finish check
log_message "Firewall status check completed"
EOF

# Make the check script executable
chmod +x /usr/local/bin/check-firewall.sh

# Create a cron job to run the check script daily
log_info "Creating cron job for firewall status check"
echo "0 7 * * * root /usr/local/bin/check-firewall.sh" > /etc/cron.d/firewall-check

# Final message
log_info "Proxmox firewall configuration completed!"
log_info "The firewall is now enabled with secure defaults."
log_info "Management access is allowed from $mgmt_network"
log_info "Daily firewall status checks will run at 7:00 AM"
log_info "To check firewall status manually, run: /usr/local/bin/check-firewall.sh" 