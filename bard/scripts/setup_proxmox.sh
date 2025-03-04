#!/bin/bash
# Proxmox Post-Installation Setup Script
# This script automates the configuration of a fresh Proxmox installation

set -e  # Exit on any error

# Script configuration
HOSTNAME="bard"
IP_ADDRESS="192.168.1.10"  # Change this to your desired IP
GATEWAY="192.168.1.1"      # Change this to your gateway
DNS="192.168.1.1"          # Change this to your DNS server
TIMEZONE="America/New_York" # Change this to your timezone

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
log_info "Starting Proxmox post-installation setup for $HOSTNAME"
log_info "This script will configure your Proxmox server with best practices"

# Update the system
log_info "Updating system packages..."
apt update && apt upgrade -y

# Remove subscription notice
log_info "Removing subscription notice..."
sed -i.backup "s/data.status !== 'Active'/false/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
systemctl restart pveproxy.service

# Configure No-Subscription Repository
log_info "Configuring repositories..."
cat > /etc/apt/sources.list.d/pve-no-subscription.list << EOF
deb http://download.proxmox.com/debian/pve bullseye pve-no-subscription
EOF

# Comment out the enterprise repository
sed -i 's/^deb/#deb/g' /etc/apt/sources.list.d/pve-enterprise.list

# Update again with new repositories
apt update

# Install useful tools
log_info "Installing useful tools..."
apt install -y htop iftop iotop net-tools vim curl wget git zsh tmux

# Configure network (optional - be careful with this!)
read -p "Do you want to configure network settings? (y/n): " configure_network
if [[ "$configure_network" == "y" ]]; then
    log_info "Configuring network settings..."
    # This is a simplified example - you might want to create a more robust network configuration
    cat > /etc/network/interfaces << EOF
auto lo
iface lo inet loopback

auto vmbr0
iface vmbr0 inet static
        address $IP_ADDRESS/24
        gateway $GATEWAY
        bridge_ports eth0
        bridge_stp off
        bridge_fd 0
EOF
    log_warn "Network configuration has been updated. You may need to reboot for changes to take effect."
fi

# Set hostname
log_info "Setting hostname to $HOSTNAME..."
hostnamectl set-hostname $HOSTNAME

# Set timezone
log_info "Setting timezone to $TIMEZONE..."
timedatectl set-timezone $TIMEZONE

# Setup SSH keys (optional)
read -p "Do you want to set up SSH keys? (y/n): " setup_ssh
if [[ "$setup_ssh" == "y" ]]; then
    log_info "Setting up SSH keys..."
    mkdir -p /root/.ssh
    # You would typically add your public key here
    echo "# Add your public SSH key here" > /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/authorized_keys
    log_info "Please edit /root/.ssh/authorized_keys to add your public SSH key"
fi

# Configure storage
log_info "Running storage configuration script..."
bash "$(dirname "$0")/configure_storage.sh"

# Configure backup
log_info "Running backup configuration script..."
bash "$(dirname "$0")/configure_backup.sh"

# Configure firewall
log_info "Running firewall configuration script..."
bash "$(dirname "$0")/configure_firewall.sh"

# Final message
log_info "Proxmox post-installation setup completed!"
log_info "You may need to reboot your system for all changes to take effect."
log_info "Run 'reboot' to restart the system." 