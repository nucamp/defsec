#!/usr/bin/env bash

# Nucamp DefSec VM Setup Script - Curl | Bash Version
# This script sets up Ubuntu VMs using multipass with security tools
# Usage: curl -fsSL <script-url> | bash

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
readonly SCRIPT_NAME="nucamp-vm-setup"
readonly LOG_FILE="/tmp/nucamp-setup-$(date +%s).log"
readonly TEMP_DIR="$HOME/.cache/nucamp-setup-$$"

# VM Configuration
readonly VM_NAMES=("nucamp-ubuntu-machine-1" "nucamp-ubuntu-machine-2")
readonly VM_CPUS=2
readonly VM_MEMORY="2G"
readonly VM_DISK="20GB"
readonly VM_OS_PRIMARY="noble"
readonly VM_OS_FALLBACK="jammy"
readonly VM_OS_DISPLAY_PRIMARY="24.04"
readonly VM_OS_DISPLAY_FALLBACK="22.04"
readonly SETUP_SCRIPT_URL="https://raw.githubusercontent.com/nucamp/defsec/refs/heads/main/kali/setup.sh"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Global state
CURL_EXECUTION=false
AUTO_CONFIRM=false

# Detect execution method
detect_execution_method() {
    if [[ ! -t 0 ]] && [[ "${BASH_SOURCE[0]:-}" == "/dev/stdin" || "${BASH_SOURCE[0]:-}" == "bash" ]]; then
        CURL_EXECUTION=true
        AUTO_CONFIRM=true
    fi
}

# Logging functions
log() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" | tee -a "$LOG_FILE" 2>/dev/null || echo "$msg"
}

log_info() {
    local msg="${BLUE}[INFO]${NC} $*"
    echo -e "$msg" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "$msg"
}

log_success() {
    local msg="${GREEN}[SUCCESS]${NC} $*"
    echo -e "$msg" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "$msg"
}

log_warning() {
    local msg="${YELLOW}[WARNING]${NC} $*"
    echo -e "$msg" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "$msg"
}

log_error() {
    local msg="${RED}[ERROR]${NC} $*"
    echo -e "$msg" | tee -a "$LOG_FILE" 2>/dev/null >&2 || echo -e "$msg" >&2
}

log_header() {
    echo -e "\n${BOLD}${BLUE}$*${NC}\n"
}

log_step() {
    echo -e "${GREEN}▶${NC} $*"
}

# Progress indicator
show_progress() {
    local -r msg="$1"
    local -r delay="${2:-0.1}"
    
    echo -n "$msg"
    for i in {1..3}; do
        sleep "$delay"
        echo -n "."
    done
    echo " done"
}

# Error handling
cleanup() {
    local exit_code=$?
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR" 2>/dev/null || true
    fi
    if [[ $exit_code -ne 0 ]]; then
        log_error "Setup failed with exit code $exit_code"
        echo -e "\n${RED}╔════════════════════════════════════════╗"
        echo -e "║              Setup Failed              ║"
        echo -e "╚════════════════════════════════════════╝${NC}"
        echo -e "\nCheck the log file for details: ${YELLOW}$LOG_FILE${NC}"
        
        # Provide specific recovery instructions based on common issues
        if grep -q "device not yet seeded" "$LOG_FILE" 2>/dev/null; then
            echo -e "\n${YELLOW}Snapd Seeding Issue Detected (Arch Linux):${NC}"
            echo -e "  ${GREEN}Automated fix available:${NC}"
            echo -e "  ${BLUE}curl -fsSL https://raw.githubusercontent.com/nucamp/defsec/main/unix-setup/fix-snapd-arch.sh | bash${NC}"
            echo -e "\n  ${YELLOW}Or manual steps:${NC}"
            echo -e "  ${BLUE}sudo systemctl restart snapd${NC}           # Restart snapd service"
            echo -e "  ${BLUE}sudo snap wait system seed.loaded${NC}      # Wait for seeding"
            echo -e "  ${BLUE}sudo snap install hello-world${NC}          # Test snap functionality"
        elif grep -q "multipass" "$LOG_FILE" 2>/dev/null; then
            echo -e "\n${YELLOW}Multipass Issue Detected:${NC}"
            echo -e "  ${BLUE}multipass list${NC}                         # Check existing VMs"
            echo -e "  ${BLUE}sudo systemctl status multipass${NC}        # Check service status"
            echo -e "  ${BLUE}sudo snap restart multipass${NC}            # Restart multipass"
        else
            echo -e "\n${YELLOW}General Debugging:${NC}"
            echo -e "  ${BLUE}sudo systemctl status snapd${NC}            # Check snapd status"
            echo -e "  ${BLUE}sudo journalctl -u snapd${NC}               # View snapd logs"
            echo -e "  ${BLUE}df -h${NC}                                  # Check disk space"
        fi
        
        echo -e "\n${YELLOW}If issues persist:${NC}"
        echo -e "  1. Reboot the system and try again"
        echo -e "  2. Check system requirements (4GB RAM, 40GB disk)"
        echo -e "  3. Ensure stable internet connection"
    fi
}

trap cleanup EXIT

error_exit() {
    log_error "$1"
    exit "${2:-1}"
}

# Utility functions
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

is_root() {
    [[ $EUID -eq 0 ]]
}

# User confirmation function
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local response
    
    if [[ "$CURL_EXECUTION" == true ]]; then
        # In curl|bash mode, for security-related prompts, use interactive mode
        if [[ "$prompt" == *"AppArmor"* ]]; then
            log_warning "Security configuration required - switching to interactive mode"
            echo -e "${YELLOW}Note: This requires user input for security configuration${NC}"
        else
            # For non-security prompts, use sensible defaults
            case "$default" in
                "y"|"yes") 
                    log_info "Auto-confirming (curl mode): $prompt [YES]"
                    return 0 
                    ;;
                *)
                    log_info "Auto-declining (curl mode): $prompt [NO]"
                    return 1
                    ;;
            esac
        fi
    fi
    
    while true; do
        if [[ "$default" == "y" || "$default" == "yes" ]]; then
            read -rp "$prompt [Y/n]: " response </dev/tty
            response=${response:-y}
        else
            read -rp "$prompt [y/N]: " response </dev/tty
            response=${response:-n}
        fi
        
        case $response in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

# AppArmor detection and setup
check_apparmor_status() {
    if [[ -f /sys/module/apparmor/parameters/enabled ]]; then
        local enabled=$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null)
        [[ "$enabled" == "Y" ]]
    else
        return 1
    fi
}

# Detect bootloader type
detect_bootloader() {
    if [[ -f /etc/default/grub ]]; then
        echo "grub"
    elif [[ -d /boot/loader/entries ]]; then
        echo "systemd-boot"
    elif [[ -f /boot/refind.conf ]]; then
        echo "refind"
    else
        echo "unknown"
    fi
}

setup_apparmor_arch() {
    log_step "Setting up AppArmor for better snap security..."
    
    # Install AppArmor if not present
    if ! command_exists aa-status; then
        log_info "Installing AppArmor package..."
        sudo pacman -S --noconfirm apparmor || error_exit "Failed to install AppArmor"
    fi
    
    # Check if AppArmor is already enabled
    if check_apparmor_status; then
        log_success "AppArmor is already enabled"
        return 0
    fi
    
    log_info "Configuring AppArmor kernel parameters..."
    
    local bootloader=$(detect_bootloader)
    log_info "Detected bootloader: $bootloader"
    
    case "$bootloader" in
        "grub")
            if grep -q "apparmor=1" /etc/default/grub 2>/dev/null; then
                log_info "AppArmor already configured in GRUB"
            else
                sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\([^"]*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 apparmor=1 security=apparmor"/' /etc/default/grub
                sudo grub-mkconfig -o /boot/grub/grub.cfg || error_exit "Failed to update GRUB configuration"
                log_success "AppArmor configured in GRUB"
            fi
            ;;
        "systemd-boot")
            log_info "Configuring AppArmor for systemd-boot..."
            local entry_file="/boot/loader/entries/arch.conf"
            if [[ -f "$entry_file" ]]; then
                if grep -q "apparmor=1" "$entry_file"; then
                    log_info "AppArmor already configured in systemd-boot"
                else
                    sudo sed -i '/^options/ s/$/ apparmor=1 security=apparmor/' "$entry_file"
                    log_success "AppArmor configured in systemd-boot"
                fi
            else
                log_warning "Could not find systemd-boot entry file"
                log_info "Please add 'apparmor=1 security=apparmor' to your kernel command line manually"
            fi
            ;;
        *)
            log_warning "Unknown bootloader detected"
            log_info "Please add 'apparmor=1 security=apparmor' to your kernel command line manually"
            log_info "Common locations:"
            log_info "  - GRUB: /etc/default/grub"
            log_info "  - systemd-boot: /boot/loader/entries/*.conf"
            ;;
    esac
    
    # Enable AppArmor service
    sudo systemctl enable apparmor || error_exit "Failed to enable AppArmor service"
    
    log_warning "AppArmor requires a reboot to take effect"
    log_info "The system will need to be rebooted for AppArmor to work properly"
    
    return 0
}

handle_apparmor_arch() {
    local distro="$1"
    
    if [[ "$distro" != "arch" && "$distro" != "manjaro" ]]; then
        return 0  # Not Arch-based, skip AppArmor setup
    fi
    
    log_header "Checking AppArmor configuration"
    
    if check_apparmor_status; then
        log_success "AppArmor is enabled and working"
        return 0
    fi
}

# System detection
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

detect_distro() {
    if [[ ! -f /etc/os-release ]]; then
        echo "unknown"
        return
    fi
    
    local distro
    distro=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    echo "$distro"
}

# Package management
install_snap_ubuntu() {
    log_step "Installing snap package manager..."
    sudo apt update -qq || error_exit "Failed to update package list"
    sudo apt install -y snapd || error_exit "Failed to install snapd"
    log_success "Snap installed successfully"
}

install_homebrew() {
    log_step "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || error_exit "Failed to install Homebrew"
    log_success "Homebrew installed successfully"
}

install_yay_arch() {
    log_step "Installing yay AUR helper..."
    sudo pacman -S --noconfirm yay || error_exit "Failed to install yay"
    log_success "Yay installed successfully"
}

install_snap_arch() {
    local use_devmode="$1"
    
    log_step "Installing snapd on Arch Linux..."
    
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    git clone https://aur.archlinux.org/snapd.git || error_exit "Failed to clone snapd AUR package"
    cd snapd
    makepkg -si --noconfirm || error_exit "Failed to build and install snapd"
    
    # Enable snapd service
    sudo systemctl enable --now snapd.socket || error_exit "Failed to enable snapd service"
    
    # Create classic snap support symlink
    sudo ln -sf /var/lib/snapd/snap /snap 2>/dev/null || true
    
    log_success "Snapd installed and enabled"
    
    if [[ "$use_devmode" == "true" ]]; then
        log_info "Using devmode - skipping extensive seeding wait"
        # Still wait a bit for basic functionality
        sleep 10
        if sudo snap version >/dev/null 2>&1; then
            log_success "Snapd is responsive (devmode)"
            return 0
        fi
    fi
    
    # Wait for snapd to seed (normal mode or devmode fallback)
    log_info "Waiting for snapd to initialize (this may take a few minutes)..."
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if sudo snap version >/dev/null 2>&1; then
            log_success "Snapd is ready"
            return 0
        fi
        
        if [ $((attempt % 10)) -eq 0 ]; then
            log_info "Still waiting for snapd to seed... (attempt $((attempt + 1))/$max_attempts)"
        fi
        
        sleep 5
        ((attempt++))
    done
    
    log_error "Snapd failed to initialize after $((max_attempts * 5)) seconds"
    log_info "This is common on fresh Arch installations."
    log_info ""
    log_info "Automated fix available:"
    log_info "  curl -fsSL https://raw.githubusercontent.com/nucamp/defsec/main/unix-setup/fix-snapd-arch.sh | bash"
    log_info ""
    log_info "Or try these manual steps:"
    log_info "  1. sudo systemctl restart snapd"
    log_info "  2. sudo snap wait system seed.loaded"
    log_info "  3. Re-run this script"
    error_exit "Snapd seeding timeout - use recovery script or manual intervention"
}

# Multipass installation
install_multipass() {
    local os="$1"
    local distro="$2"
    local use_devmode="$3"
    
    if command_exists multipass; then
        log_info "Multipass is already installed"
        return 0
    fi
    
    log_step "Installing multipass..."
    
    case "$os" in
        "linux")
            case "$distro" in
                "ubuntu"|"debian"|"linuxmint"|"pop")
                    if ! command_exists snap; then
                        install_snap_ubuntu
                    fi
                    log_info "Installing multipass via snap..."
                    sudo snap install multipass || error_exit "Failed to install multipass via snap"
                    ;;
                "arch"|"manjaro")
                    if ! command_exists yay; then
                        install_yay_arch
                    fi
                    if ! command_exists snap; then
                        install_snap_arch "$use_devmode"
                    fi
                    
                    log_info "Installing multipass via snap..."
                    
                    if [[ "$use_devmode" == "true" ]]; then
                        log_info "Using devmode installation (reduced security)"
                        sudo snap install multipass --devmode || error_exit "Failed to install multipass in devmode"
                    else
                        if ! sudo snap install multipass; then
                            log_warning "Normal installation failed, checking snapd status..."
                            
                            # Check if snapd is properly seeded
                            if ! sudo snap wait system seed.loaded 2>/dev/null; then
                                log_info "Snapd is not fully seeded, waiting 30 seconds..."
                                sleep 30
                            fi
                            
                            log_info "Retrying multipass installation..."
                            if ! sudo snap install multipass; then
                                log_warning "Retrying with devmode as fallback..."
                                sudo snap install multipass --devmode || {
                                    log_error "Multipass installation failed completely"
                                    log_info ""
                                    log_info "Use the snapd recovery script:"
                                    log_info "  curl -fsSL https://raw.githubusercontent.com/nucamp/defsec/main/unix-setup/fix-snapd-arch.sh | bash"
                                    error_exit "Failed to install multipass - use recovery script"
                                }
                            fi
                        fi
                    fi
                    ;;
                *)
                    error_exit "Unsupported Linux distribution: $distro"
                    ;;
            esac
            ;;
        "macos")
            if ! command_exists brew; then
                install_homebrew
            fi
            log_info "Installing multipass via Homebrew..."
            brew install multipass || error_exit "Failed to install multipass via brew"
            ;;
        *)
            error_exit "Unsupported operating system: $os"
            ;;
    esac
    
    # Wait for multipass to be available
    log_info "Verifying multipass installation..."
    local max_attempts=12
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if command_exists multipass && multipass version >/dev/null 2>&1; then
            log_success "Multipass installed and ready"
            return 0
        fi
        
        log_info "Waiting for multipass to become available... (attempt $((attempt + 1))/$max_attempts)"
        sleep 5
        ((attempt++))
    done
    
    error_exit "Multipass installation verification failed after $((max_attempts * 5)) seconds"
}

# Initialize multipass
initialize_multipass() {
    log_info "Initializing multipass..."
    
    # Check if multipass daemon is running
    local max_attempts=6
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if multipass list >/dev/null 2>&1; then
            log_success "Multipass daemon is responsive"
            return 0
        fi
        
        log_info "Waiting for multipass daemon... (attempt $((attempt + 1))/$max_attempts)"
        sleep 5
        ((attempt++))
    done
    
    log_warning "Multipass daemon is not responding, attempting restart..."
    if command_exists systemctl; then
        sudo systemctl restart multipass 2>/dev/null || true
    elif command_exists snap; then
        sudo snap restart multipass 2>/dev/null || true
    fi
    
    # Give it one more chance
    sleep 10
    if multipass list >/dev/null 2>&1; then
        log_success "Multipass daemon restarted successfully"
        return 0
    else
        log_error "Multipass daemon is not working properly"
        return 1
    fi
}

# Multipass utilities
detect_available_images() {
    log_info "Detecting available Ubuntu images..."
    
    local available_images
    if ! available_images=$(multipass find 2>/dev/null); then
        log_warning "Could not query available images"
        return 1
    fi
    
    echo "$available_images"
}

get_ubuntu_release() {
    local images
    if images=$(detect_available_images 2>/dev/null); then
        # Try primary version first (noble = 24.04)
        if echo "$images" | grep -q "noble\|24\.04"; then
            echo "$VM_OS_PRIMARY"
            return 0
        fi
        
        # Try fallback version (jammy = 22.04)
        if echo "$images" | grep -q "jammy\|22\.04"; then
            echo "$VM_OS_FALLBACK"
            return 0
        fi
        
        # Try to find any LTS version
        local lts_version
        lts_version=$(echo "$images" | grep -E "^[0-9]+\.[0-9]+" | head -1 | awk '{print $1}')
        if [[ -n "$lts_version" ]]; then
            echo "$lts_version"
            return 0
        fi
    fi
    
    return 1
}

# VM management
check_existing_vms() {
    log_step "Checking for existing VMs..."
    
    local existing_vms existing_names
    if existing_vms=$(multipass list --format json 2>/dev/null); then
        existing_names=$(echo "$existing_vms" | jq -r '.list[].name' 2>/dev/null || echo "")
        
        if [[ -n "$existing_names" ]]; then
            log_info "Found existing VMs:"
            echo "$existing_names" | while read -r vm_name; do
                [[ -n "$vm_name" ]] && log_info "  • $vm_name"
            done
        else
            log_info "No existing VMs found"
        fi
        
        # Check for naming conflicts
        for new_vm in "${VM_NAMES[@]}"; do
            if echo "$existing_names" | grep -q "^${new_vm}$"; then
                log_warning "VM already exists: $new_vm"
                log_info "Deleting and recreating VM: $new_vm"
                multipass delete "$new_vm" 2>/dev/null || true
                multipass purge 2>/dev/null || true
            fi
        done
    else
        log_info "Could not query existing VMs (multipass may not be fully initialized)"
    fi
}

create_vms() {
    log_step "Creating virtual machines..."
    
    # Initialize multipass
    if ! initialize_multipass; then
        error_exit "Multipass initialization failed"
    fi
    
    # Get the best Ubuntu release to use
    log_info "Finding best Ubuntu release to use..."
    local ubuntu_release
    if ubuntu_release=$(get_ubuntu_release); then
        case "$ubuntu_release" in
            "noble") log_success "Using Ubuntu ${VM_OS_DISPLAY_PRIMARY} (noble)" ;;
            "jammy") log_warning "Ubuntu ${VM_OS_DISPLAY_PRIMARY} not available, using ${VM_OS_DISPLAY_FALLBACK} (jammy)" ;;
            *) log_warning "Using available version: $ubuntu_release" ;;
        esac
    else
        log_error "Cannot determine Ubuntu release to use"
        log_info "Available images:"
        detect_available_images | head -10
        log_info "Troubleshooting steps:"
        log_info "  1. Check network: ping -c 3 8.8.8.8"
        log_info "  2. Restart multipass: sudo snap restart multipass"
        log_info "  3. Check multipass: multipass version"
        log_info "  4. Try manual launch: multipass launch --name test jammy"
        error_exit "No suitable Ubuntu release available"
    fi
    
    for vm_name in "${VM_NAMES[@]}"; do
        local display_version
        case "$ubuntu_release" in
            "noble") display_version="24.04 LTS (noble)" ;;
            "jammy") display_version="22.04 LTS (jammy)" ;;
            *) display_version="$ubuntu_release" ;;
        esac
        log_info "Creating VM: $vm_name (${VM_CPUS} CPUs, ${VM_MEMORY} RAM, ${VM_DISK} disk) with Ubuntu $display_version"
        
        show_progress "  Setting up $vm_name" 0.5
        
        if ! multipass launch \
            --cpus "$VM_CPUS" \
            --memory "$VM_MEMORY" \
            --disk "$VM_DISK" \
            --name "$vm_name" \
            "$ubuntu_release"; then
            
            log_error "Failed to create VM: $vm_name"
            log_info "Troubleshooting multipass issues..."
            
            # Try to diagnose the issue
            log_info "Multipass diagnostics:"
            log_info "Version: $(multipass version 2>/dev/null || echo 'Failed')"
            log_info "Available images:"
            multipass find 2>/dev/null | head -5 || log_warning "Cannot list images"
            
            log_info "Network connectivity test:"
            if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
                log_success "Network connectivity OK"
            else
                log_error "Network connectivity failed"
            fi
            
            error_exit "Failed to create VM: $vm_name"
        fi
        
        log_success "Created VM: $vm_name"
    done
}

test_vm_connectivity() {
    log_step "Testing VM network connectivity..."

    for vm_name in "${VM_NAMES[@]}"; do
        log_info "Testing connectivity for: $vm_name"

        # Give the VM extra time to fully initialize
        sleep 10

        # Test connectivity with retries
        local max_attempts=5
        local attempt=0

        while [ $attempt -lt $max_attempts ]; do
            if multipass exec "$vm_name" -- ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1; then
                log_success "Network connectivity OK for: $vm_name"
                break
            else
                log_info "Waiting for network connectivity... (attempt $((attempt + 1))/$max_attempts)"
                sleep 5
                ((attempt++))
            fi
        done

        if [ $attempt -eq $max_attempts ]; then
            error_exit "Network connectivity test failed for VM: $vm_name"
        fi
    done
}

setup_security_tools() {
    local target_vm="nucamp-ubuntu-machine-2"
    log_step "Installing security tools on: $target_vm"
    
    # Download setup script to a location snap can access
    local setup_script="$HOME/ubuntu_setup.sh"
    
    log_info "Downloading security tools setup script..."
    if curl -fsSL "$SETUP_SCRIPT_URL" -o "$setup_script"; then
        log_success "Downloaded setup script"
    else
        error_exit "Failed to download setup script from: $SETUP_SCRIPT_URL"
    fi
    
    # Transfer script to VM
    log_info "Transferring setup script to VM..."
    multipass transfer "$setup_script" "$target_vm:/home/ubuntu/" || error_exit "Failed to transfer setup script to VM"
    
    # Clean up local script
    rm -f "$setup_script" 2>/dev/null || true
    
    # Execute setup script
    log_info "Executing security tools installation (this may take several minutes)..."
    
    if multipass exec "$target_vm" -- sudo bash /home/ubuntu/ubuntu_setup.sh; then
        log_success "Security tools installation completed successfully"
    else
        log_warning "Security tools installation completed with warnings"
        log_info "The VM is functional but may need manual configuration"
    fi
}

# Main setup process
main() {
    # Detect execution method
    detect_execution_method
    
    # Initialize logging
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || LOG_FILE="/tmp/nucamp-setup.log"
    
    # Show banner
    echo -e "\n${GREEN}╔══════════════════════════════════════════════════╗"
    echo -e "║            🔐 Nucamp DefSec VM Setup             ║"
    echo -e "╚══════════════════════════════════════════════════╝${NC}\n"
    
    log "Starting Nucamp DefSec VM setup"
    
    if [[ "$CURL_EXECUTION" == true ]]; then
        log_info "Running in curl|bash mode - automatic setup enabled"
    fi
    
    echo -e "This script will:"
    echo -e "  ${BLUE}1.${NC} Install required package managers and multipass"
    echo -e "  ${BLUE}2.${NC} Create two Ubuntu VMs with security tools"
    echo -e "  ${BLUE}3.${NC} Test network connectivity"
    echo -e "  ${BLUE}4.${NC} Configure security tools on one VM"
    echo
    echo -e "VMs to be created:"
    printf '  • %s\n' "${VM_NAMES[@]}"
    echo
    echo -e "Log file: ${YELLOW}$LOG_FILE${NC}"
    echo
    
    # Preflight checks
    log_header "Performing preflight checks"
    
    if is_root; then
        error_exit "This script should not be run as root"
    fi
    
    # Check for required commands
    local missing_commands=()
    for cmd in curl jq git; do
        if ! command_exists "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        error_exit "Missing required commands: ${missing_commands[*]}"
    fi
    
    # Check internet connectivity
    if ! curl -s --connect-timeout 5 https://1.1.1.1 >/dev/null 2>&1; then
        error_exit "No internet connectivity detected"
    fi
    
    log_success "Preflight checks passed"
    
    # System detection
    log_header "Detecting system configuration"
    
    local os distro
    os=$(detect_os)
    distro=$(detect_distro)
    
    log_info "Operating system: $os"
    log_info "Distribution: $distro"
    
    if [[ "$os" == "unknown" ]]; then
        error_exit "Unsupported operating system"
    fi
    
    # Handle AppArmor configuration for Arch Linux
    local use_devmode="false"
    if [[ "$distro" == "arch" || "$distro" == "manjaro" ]]; then
        if ! handle_apparmor_arch "$distro"; then
            use_devmode="true"
        fi
    fi
    
    # Install dependencies
    log_header "Installing dependencies"
    install_multipass "$os" "$distro" "$use_devmode"
    
    # VM operations
    log_header "Setting up virtual machines"
    check_existing_vms
    create_vms
    test_vm_connectivity
    setup_security_tools
    
    # Success message
    echo -e "\n${GREEN}╔══════════════════════════════════════════════════╗"
    echo -e "║                 🎉 Setup Complete!               ║"
    echo -e "╚══════════════════════════════════════════════════╝${NC}\n"
    
    log_success "Nucamp DefSec VM setup completed successfully!"
    
    echo -e "Your VMs are ready:"
    printf '  • %s\n' "${VM_NAMES[@]}"
    echo
    echo -e "${BOLD}Next steps:${NC}"
    echo -e "  ${GREEN}•${NC} Access your VMs: ${BLUE}multipass shell <vm-name>${NC}"
    echo -e "  ${GREEN}•${NC} List all VMs: ${BLUE}multipass list${NC}"
    echo -e "  ${GREEN}•${NC} VM info: ${BLUE}multipass info <vm-name>${NC}"
    echo
    echo -e "${BOLD}VM Management:${NC}"
    echo -e "  ${BLUE}multipass stop <vm-name>${NC}    # Stop a VM"
    echo -e "  ${BLUE}multipass start <vm-name>${NC}   # Start a VM"
    echo -e "  ${BLUE}multipass delete <vm-name>${NC}  # Delete a VM"
    echo -e "  ${BLUE}multipass purge${NC}             # Remove deleted VMs"
    echo
    echo -e "Log file saved to: ${YELLOW}$LOG_FILE${NC}"
    echo -e "\n${GREEN}Happy hacking! 🔐${NC}\n"
}

# Handle command line arguments for local execution
if [[ "${BASH_SOURCE[0]:-}" != "/dev/stdin" && "${BASH_SOURCE[0]:-}" != "bash" ]]; then
    case "${1:-}" in
        -h|--help)
            cat << 'EOF'
Nucamp DefSec VM Setup Script

USAGE:
    # Remote execution (recommended):
    curl -fsSL <script-url> | bash
    
    # Local execution:
    ./setup-improved.sh
    
DESCRIPTION:
    Sets up two Ubuntu VMs with security/penetration testing tools:
    - nucamp-ubuntu-machine-1: Basic Ubuntu VM
    - nucamp-ubuntu-machine-2: Ubuntu VM with security tools

REQUIREMENTS:
    - Linux (Ubuntu/Debian/Arch) or macOS
    - Internet connection
    - At least 4GB RAM and 40GB disk space
    - curl, jq, git commands

VMs CREATED:
    • nucamp-ubuntu-machine-1 (2 CPUs, 2GB RAM, 20GB disk)
    • nucamp-ubuntu-machine-2 (2 CPUs, 2GB RAM, 20GB disk) + security tools

LOG FILES:
    Logs are saved to /tmp/nucamp-setup-<timestamp>.log

EOF
            exit 0
            ;;
        *)
            # Run main function for local execution
            main "$@"
            ;;
    esac
else
    # Run main function for curl|bash execution
    main "$@"
fi
