#!/bin/bash
# Proxmox Storage Configuration Script
# This script configures storage for Proxmox based on the available hardware

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
log_info "Starting Proxmox storage configuration"

# Detect available disks
log_info "Detecting available disks..."
lsblk -o NAME,SIZE,MODEL,SERIAL,MOUNTPOINT

# Based on the hardware in the README:
# - 2x1tb NVME SSD Raid 1
# - 2x6tb HDD Raid 1
# - 1x1tb SSD
# - 1x500gb SSD

# Ask for confirmation before proceeding
log_warn "This script will configure storage based on your hardware."
log_warn "Make sure you have backed up any important data before proceeding."
read -p "Do you want to continue? (y/n): " continue_setup
if [[ "$continue_setup" != "y" ]]; then
    log_info "Storage configuration aborted."
    exit 0
fi

# Function to create ZFS pools
create_zfs_pool() {
    local pool_name=$1
    local raid_level=$2
    shift 2
    local disks=("$@")
    
    # Check if pool already exists
    if zpool list | grep -q "$pool_name"; then
        log_warn "ZFS pool '$pool_name' already exists. Skipping creation."
        return
    }
    
    # Create the pool based on RAID level
    log_info "Creating ZFS pool '$pool_name' with RAID level $raid_level using disks: ${disks[*]}"
    
    if [[ "$raid_level" == "mirror" ]]; then
        zpool create -f "$pool_name" mirror "${disks[@]}"
    elif [[ "$raid_level" == "raidz1" ]]; then
        zpool create -f "$pool_name" raidz1 "${disks[@]}"
    elif [[ "$raid_level" == "raidz2" ]]; then
        zpool create -f "$pool_name" raidz2 "${disks[@]}"
    elif [[ "$raid_level" == "raidz3" ]]; then
        zpool create -f "$pool_name" raidz3 "${disks[@]}"
    else
        log_error "Unsupported RAID level: $raid_level"
        return 1
    fi
    
    # Set compression and other ZFS properties
    zfs set compression=lz4 "$pool_name"
    zfs set atime=off "$pool_name"
}

# Interactive disk selection for NVME RAID 1
log_info "Setting up NVME RAID 1 pool for VM storage"
log_info "Please select the two 1TB NVME SSDs for RAID 1:"
read -p "First NVME SSD (e.g., nvme0n1): " nvme1
read -p "Second NVME SSD (e.g., nvme1n1): " nvme2

# Create NVME RAID 1 pool
if [[ -n "$nvme1" && -n "$nvme2" ]]; then
    create_zfs_pool "nvme-mirror" "mirror" "/dev/$nvme1" "/dev/$nvme2"
    
    # Create datasets for VMs and containers
    log_info "Creating datasets for VMs and containers"
    zfs create nvme-mirror/vm-disks
    zfs create nvme-mirror/ct-disks
    
    # Add to Proxmox
    log_info "Adding ZFS storage to Proxmox configuration"
    pvesm add zfspool vm-storage -pool nvme-mirror/vm-disks -content images,rootdir
    pvesm add zfspool ct-storage -pool nvme-mirror/ct-disks -content rootdir
else
    log_warn "NVME SSDs not specified. Skipping NVME RAID 1 setup."
fi

# Interactive disk selection for HDD RAID 1
log_info "Setting up HDD RAID 1 pool for backup storage"
log_info "Please select the two 6TB HDDs for RAID 1:"
read -p "First HDD (e.g., sda): " hdd1
read -p "Second HDD (e.g., sdb): " hdd2

# Create HDD RAID 1 pool
if [[ -n "$hdd1" && -n "$hdd2" ]]; then
    create_zfs_pool "hdd-mirror" "mirror" "/dev/$hdd1" "/dev/$hdd2"
    
    # Create datasets for backups and shared storage
    log_info "Creating datasets for backups and shared storage"
    zfs create hdd-mirror/backups
    zfs create hdd-mirror/shared
    
    # Add to Proxmox
    log_info "Adding ZFS storage to Proxmox configuration"
    pvesm add zfspool backup-storage -pool hdd-mirror/backups -content backup
    pvesm add zfspool shared-storage -pool hdd-mirror/shared -content images,iso,vztmpl
else
    log_warn "HDDs not specified. Skipping HDD RAID 1 setup."
fi

# Interactive disk selection for additional SSDs
log_info "Setting up additional SSDs"
read -p "1TB SSD for ISO and templates (e.g., sdc): " ssd1
read -p "500GB SSD for special purposes (e.g., sdd): " ssd2

# Configure 1TB SSD
if [[ -n "$ssd1" ]]; then
    log_info "Setting up 1TB SSD for ISO and templates"
    
    # Create partition table
    parted -s "/dev/$ssd1" mklabel gpt
    parted -s "/dev/$ssd1" mkpart primary ext4 0% 100%
    
    # Format partition
    mkfs.ext4 "/dev/${ssd1}1"
    
    # Create mount point
    mkdir -p /mnt/iso_templates
    
    # Add to fstab
    echo "/dev/${ssd1}1 /mnt/iso_templates ext4 defaults 0 2" >> /etc/fstab
    
    # Mount
    mount "/dev/${ssd1}1" /mnt/iso_templates
    
    # Add to Proxmox
    pvesm add dir iso-templates -path /mnt/iso_templates -content iso,vztmpl
else
    log_warn "1TB SSD not specified. Skipping setup."
fi

# Configure 500GB SSD
if [[ -n "$ssd2" ]]; then
    log_info "Setting up 500GB SSD for special purposes"
    
    # Create partition table
    parted -s "/dev/$ssd2" mklabel gpt
    parted -s "/dev/$ssd2" mkpart primary ext4 0% 100%
    
    # Format partition
    mkfs.ext4 "/dev/${ssd2}1"
    
    # Create mount point
    mkdir -p /mnt/special
    
    # Add to fstab
    echo "/dev/${ssd2}1 /mnt/special ext4 defaults 0 2" >> /etc/fstab
    
    # Mount
    mount "/dev/${ssd2}1" /mnt/special
    
    # Add to Proxmox
    pvesm add dir special-storage -path /mnt/special -content images,iso,vztmpl
else
    log_warn "500GB SSD not specified. Skipping setup."
fi

# Display storage configuration
log_info "Storage configuration completed. Current storage configuration:"
pvesm status

# Final message
log_info "Proxmox storage configuration completed!"
log_info "You may need to reboot your system for all changes to take effect." 