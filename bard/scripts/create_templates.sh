#!/bin/bash
# Proxmox VM Template Creation Script
# This script creates common VM templates for quick deployment

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
log_info "Starting Proxmox VM template creation"

# Check if VM storage exists
if ! pvesm status | grep -q "vm-storage"; then
    log_error "VM storage 'vm-storage' not found. Please run the storage configuration script first."
    exit 1
fi

# Create a directory for ISO downloads
mkdir -p /var/lib/vz/template/iso
cd /var/lib/vz/template/iso

# Function to download ISO if it doesn't exist
download_iso() {
    local iso_name=$1
    local iso_url=$2
    
    if [ -f "$iso_name" ]; then
        log_info "ISO $iso_name already exists. Skipping download."
    else
        log_info "Downloading $iso_name..."
        wget -O "$iso_name" "$iso_url"
        log_info "Download completed: $iso_name"
    fi
}

# Ask which templates to create
log_info "Select which VM templates to create:"
read -p "Ubuntu Server 22.04 (y/n, default: y): " create_ubuntu
create_ubuntu=${create_ubuntu:-"y"}

read -p "Debian 12 (y/n, default: y): " create_debian
create_debian=${create_debian:-"y"}

read -p "CentOS Stream 9 (y/n, default: n): " create_centos
create_centos=${create_centos:-"n"}

read -p "Alpine Linux (y/n, default: n): " create_alpine
create_alpine=${create_alpine:-"n"}

read -p "Windows Server 2022 (requires ISO) (y/n, default: n): " create_windows
create_windows=${create_windows:-"n"}

# Download ISOs based on selection
if [[ "$create_ubuntu" == "y" ]]; then
    download_iso "ubuntu-22.04-live-server-amd64.iso" "https://releases.ubuntu.com/22.04/ubuntu-22.04.3-live-server-amd64.iso"
fi

if [[ "$create_debian" == "y" ]]; then
    download_iso "debian-12-amd64-netinst.iso" "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.4.0-amd64-netinst.iso"
fi

if [[ "$create_centos" == "y" ]]; then
    download_iso "CentOS-Stream-9-latest-x86_64-dvd1.iso" "https://mirror.stream.centos.org/9-stream/BaseOS/x86_64/iso/CentOS-Stream-9-latest-x86_64-dvd1.iso"
fi

if [[ "$create_alpine" == "y" ]]; then
    download_iso "alpine-standard-3.19.0-x86_64.iso" "https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-standard-3.19.0-x86_64.iso"
fi

if [[ "$create_windows" == "y" ]]; then
    log_warn "Windows Server 2022 ISO must be downloaded manually due to licensing."
    log_warn "Please download it from Microsoft's website and place it in /var/lib/vz/template/iso/"
fi

# Function to create a VM template
create_vm_template() {
    local template_name=$1
    local iso_name=$2
    local disk_size=$3
    local memory=$4
    local cores=$5
    local vm_id=$6
    local os_type=$7
    
    log_info "Creating $template_name template (VM ID: $vm_id)..."
    
    # Create the VM
    qm create $vm_id --name "$template_name" \
        --memory $memory \
        --cores $cores \
        --net0 virtio,bridge=vmbr0 \
        --bootdisk scsi0 \
        --scsihw virtio-scsi-pci \
        --ostype $os_type \
        --iso "$iso_name" \
        --onboot 0 \
        --agent 1
    
    # Add a disk
    qm set $vm_id --scsi0 vm-storage:$disk_size
    
    # Set display to VNC
    qm set $vm_id --vga std
    
    # Enable QEMU Guest Agent
    qm set $vm_id --serial0 socket --vga serial0
    
    # Convert to template
    qm template $vm_id
    
    log_info "$template_name template created successfully!"
}

# Create templates based on selection
if [[ "$create_ubuntu" == "y" ]]; then
    create_vm_template "ubuntu-2204-template" "local:iso/ubuntu-22.04-live-server-amd64.iso" "32G" "2048" "2" "9000" "l26"
fi

if [[ "$create_debian" == "y" ]]; then
    create_vm_template "debian-12-template" "local:iso/debian-12-amd64-netinst.iso" "32G" "2048" "2" "9001" "l26"
fi

if [[ "$create_centos" == "y" ]]; then
    create_vm_template "centos-9-template" "local:iso/CentOS-Stream-9-latest-x86_64-dvd1.iso" "32G" "2048" "2" "9002" "l26"
fi

if [[ "$create_alpine" == "y" ]]; then
    create_vm_template "alpine-3.19-template" "local:iso/alpine-standard-3.19.0-x86_64.iso" "8G" "1024" "1" "9003" "l26"
fi

if [[ "$create_windows" == "y" ]]; then
    if [ -f "/var/lib/vz/template/iso/Windows_Server_2022.iso" ]; then
        create_vm_template "windows-2022-template" "local:iso/Windows_Server_2022.iso" "64G" "4096" "4" "9004" "win11"
    else
        log_error "Windows Server 2022 ISO not found. Please download it manually."
    fi
fi

# Create a script to create a VM from template
log_info "Creating helper script to clone VMs from templates..."

cat > /usr/local/bin/clone-vm-template.sh << 'EOF'
#!/bin/bash
# Script to clone a VM from a template

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Check arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <template-id> <new-vm-name> [new-vm-id]"
    echo "Example: $0 9000 web-server 101"
    exit 1
fi

TEMPLATE_ID=$1
NEW_VM_NAME=$2
NEW_VM_ID=${3:-$(pvesh get /cluster/nextid)}

# Clone the template
qm clone $TEMPLATE_ID $NEW_VM_ID --name $NEW_VM_NAME

# Start the VM
qm start $NEW_VM_ID

echo "VM '$NEW_VM_NAME' (ID: $NEW_VM_ID) created from template $TEMPLATE_ID and started."
echo "Access the console with: qm terminal $NEW_VM_ID"
EOF

# Make the clone script executable
chmod +x /usr/local/bin/clone-vm-template.sh

# Create a script to create a container template
log_info "Creating LXC container templates..."

cat > /usr/local/bin/create-ct-template.sh << 'EOF'
#!/bin/bash
# Script to download and create LXC container templates

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Download latest container templates
pveam update

# List available templates
echo "Available container templates:"
pveam available

# Download common templates
pveam download local debian-12-standard_12.0-1_amd64.tar.zst
pveam download local ubuntu-22.04-standard_22.04-1_amd64.tar.zst
pveam download local centos-9-default_20230701_amd64.tar.xz
pveam download local alpine-3.19-default_20231218_amd64.tar.xz

echo "Container templates downloaded successfully."
echo "To create a container, use the Proxmox web interface or the 'pct' command."
EOF

# Make the container template script executable
chmod +x /usr/local/bin/create-ct-template.sh

# Run the container template script
log_info "Downloading LXC container templates..."
/usr/local/bin/create-ct-template.sh

# Final message
log_info "Proxmox VM template creation completed!"
log_info "To create a VM from a template, run: /usr/local/bin/clone-vm-template.sh <template-id> <new-vm-name> [new-vm-id]"
log_info "Example: /usr/local/bin/clone-vm-template.sh 9000 web-server 101" 