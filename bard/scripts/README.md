# Proxmox Server Setup Scripts

This directory contains scripts to automate the setup and configuration of a Proxmox server after a fresh installation. These scripts are designed to help quickly recover your homelab environment in case of failure.

## Prerequisites

- A fresh installation of Proxmox VE (tested with version 7.x and 8.x)
- Root access to the Proxmox server
- Network connectivity to download packages and ISO images

## Getting Started

1. Clone this repository to your Proxmox server:
   ```bash
   git clone https://github.com/yourusername/homelab.git
   cd homelab/bard/scripts
   ```

2. Make all scripts executable:
   ```bash
   chmod +x *.sh
   ```

3. Run the main setup script:
   ```bash
   ./setup_proxmox.sh
   ```

## Available Scripts

### Main Scripts

- **setup_proxmox.sh**: The main script that orchestrates the entire setup process
- **configure_storage.sh**: Configures storage based on available disks
- **configure_backup.sh**: Sets up automated backup jobs
- **configure_firewall.sh**: Configures the Proxmox firewall with secure defaults
- **create_templates.sh**: Creates VM and container templates

### Helper Scripts

These scripts are created by the main scripts and installed in `/usr/local/bin/`:

- **check-firewall.sh**: Checks the status of the Proxmox firewall
- **verify-backups.sh**: Verifies the integrity of backup files
- **clone-vm-template.sh**: Clones a VM from a template
- **create-ct-template.sh**: Downloads and creates LXC container templates

## Script Details

### setup_proxmox.sh

This is the main script that performs the following tasks:

- Updates the system packages
- Removes the subscription notice
- Configures repositories for non-subscription use
- Installs useful tools
- Configures network settings (optional)
- Sets hostname and timezone
- Sets up SSH keys (optional)
- Calls other configuration scripts

Usage:
```bash
./setup_proxmox.sh
```

### configure_storage.sh

This script configures storage based on the available disks:

- Detects available disks
- Creates ZFS pools for RAID configurations
- Sets up mount points for additional disks
- Adds storage to Proxmox configuration

Usage:
```bash
./configure_storage.sh
```

### configure_backup.sh

This script sets up automated backup jobs:

- Configures backup retention settings
- Sets up backup schedule
- Creates a backup job for all VMs and containers
- Creates a backup verification script

Usage:
```bash
./configure_backup.sh
```

### configure_firewall.sh

This script configures the Proxmox firewall:

- Enables the firewall with secure defaults
- Configures rules for management access
- Sets up rules for Proxmox cluster communication
- Creates a firewall status check script

Usage:
```bash
./configure_firewall.sh
```

### create_templates.sh

This script creates VM and container templates:

- Downloads ISO images for common operating systems
- Creates VM templates for quick deployment
- Downloads LXC container templates
- Creates helper scripts for VM and container creation

Usage:
```bash
./create_templates.sh
```

## Customization

You can customize the scripts by editing the variables at the top of each script. Common customization options include:

- IP address and network settings
- Hostname and timezone
- Backup schedule and retention
- Firewall rules
- VM template specifications

## Troubleshooting

If you encounter issues with the scripts, check the following:

1. Make sure all scripts are executable (`chmod +x *.sh`)
2. Verify that you have root access
3. Check network connectivity
4. Review the script output for error messages
5. Check system logs (`/var/log/syslog`)

## Contributing

Feel free to contribute to these scripts by submitting pull requests or opening issues for bugs and feature requests.

## License

This project is licensed under the MIT License - see the LICENSE file for details. 