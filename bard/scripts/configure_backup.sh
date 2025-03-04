#!/bin/bash
# Proxmox Backup Configuration Script
# This script configures backup jobs for Proxmox VMs and containers

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
log_info "Starting Proxmox backup configuration"

# Check if backup storage exists
if ! pvesm status | grep -q "backup-storage"; then
    log_error "Backup storage 'backup-storage' not found. Please run the storage configuration script first."
    exit 1
fi

# Configure backup retention
log_info "Configuring backup retention settings"
read -p "Number of backups to keep (default: 7): " backup_count
backup_count=${backup_count:-7}

# Configure backup schedule
log_info "Configuring backup schedule"
read -p "Backup time (HH:MM, default: 01:00): " backup_time
backup_time=${backup_time:-"01:00"}

read -p "Backup days (mon,tue,wed,thu,fri,sat,sun, default: sat): " backup_days
backup_days=${backup_days:-"sat"}

# Configure backup compression
log_info "Configuring backup compression"
read -p "Compression level (0-9, default: 7): " compression
compression=${compression:-7}

# Configure backup mode
log_info "Configuring backup mode"
read -p "Backup mode (snapshot, suspend, stop, default: snapshot): " mode
mode=${mode:-"snapshot"}

# Create backup job for all VMs
log_info "Creating backup job for all VMs and containers"

# Generate a unique ID for the backup job
job_id=$(date +%s)

# Create the backup job
cat > /etc/pve/jobs.cfg << EOF
vzdump: $job_id
        all: 1
        compress: $compression
        enabled: 1
        exclude:
        ionice: 7
        lockwait: 180
        mailnotification: always
        mailto: root
        maxfiles: $backup_count
        mode: $mode
        node: $(hostname -s)
        pigz: 1
        quiet: 0
        remove: 1
        schedule: $backup_time $backup_days
        stopwait: 10
        storage: backup-storage
        tmpdir: /tmp
EOF

log_info "Backup job created with ID: $job_id"

# Create a script to verify backups
log_info "Creating backup verification script"

cat > /usr/local/bin/verify-backups.sh << 'EOF'
#!/bin/bash
# Script to verify Proxmox backups

# Set variables
BACKUP_DIR=$(pvesm path backup-storage)
LOG_FILE="/var/log/backup-verification.log"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Clear log file
> "$LOG_FILE"

# Start verification
log_message "Starting backup verification"

# Check if backup directory exists
if [ ! -d "$BACKUP_DIR" ]; then
    log_message "ERROR: Backup directory $BACKUP_DIR does not exist"
    exit 1
fi

# Count backup files
BACKUP_COUNT=$(find "$BACKUP_DIR" -name "*.vma.zst" -o -name "*.vma.lzo" -o -name "*.tar.zst" -o -name "*.tar.lzo" | wc -l)
log_message "Found $BACKUP_COUNT backup files"

# Verify each backup file
find "$BACKUP_DIR" -name "*.vma.zst" -o -name "*.vma.lzo" -o -name "*.tar.zst" -o -name "*.tar.lzo" | while read -r backup_file; do
    log_message "Verifying: $(basename "$backup_file")"
    
    # Check file integrity based on extension
    if [[ "$backup_file" == *.zst ]]; then
        if zstd -t "$backup_file" > /dev/null 2>&1; then
            log_message "✓ Integrity check passed: $(basename "$backup_file")"
        else
            log_message "✗ Integrity check FAILED: $(basename "$backup_file")"
        fi
    elif [[ "$backup_file" == *.lzo ]]; then
        if lzop -t "$backup_file" > /dev/null 2>&1; then
            log_message "✓ Integrity check passed: $(basename "$backup_file")"
        else
            log_message "✗ Integrity check FAILED: $(basename "$backup_file")"
        fi
    else
        log_message "? Unknown format: $(basename "$backup_file")"
    fi
done

# Finish verification
log_message "Backup verification completed"

# Send email with results
mail -s "Proxmox Backup Verification Report - $(hostname)" root < "$LOG_FILE"
EOF

# Make the verification script executable
chmod +x /usr/local/bin/verify-backups.sh

# Create a cron job to run the verification script weekly
log_info "Creating cron job for backup verification"
echo "0 8 * * sun root /usr/local/bin/verify-backups.sh" > /etc/cron.d/backup-verification

# Final message
log_info "Proxmox backup configuration completed!"
log_info "Backups will run at $backup_time on $backup_days"
log_info "Backup verification will run every Sunday at 8:00 AM" 