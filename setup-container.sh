#!/bin/bash
# Kubernetes Container Runtime Setup Script
# Author: System Administrator
# Version: 1.0
# License: MIT
# Description: Sets up containerd as the container runtime for Kubernetes
# Usage: sudo ./setup-container.sh

set -euo pipefail

# Logging function
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}"
}

# Error handling function
handle_error() {
    local exit_code=$1
    local error_message=$2
    log "ERROR" "${error_message}"
    exit ${exit_code}
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    handle_error 1 "This script must be run as root. Please use sudo."
fi

# Detect platform and OS
log "INFO" "Detecting system information..."
MYOS=$(hostnamectl | awk '/Operating/ { print $3 }') || handle_error 2 "Failed to detect OS"
OSVERSION=$(hostnamectl | awk '/Operating/ { print $4 }') || handle_error 2 "Failed to detect OS version"

# Detect architecture
case $(arch) in
    aarch64) PLATFORM=arm64 ;;
    x86_64)  PLATFORM=amd64 ;;
    *)       handle_error 3 "Unsupported architecture: $(arch)" ;;
esac

log "INFO" "Detected: OS=${MYOS}, Version=${OSVERSION}, Platform=${PLATFORM}"

# Install required tools
log "INFO" "Installing required tools..."
if ! sudo apt install -y jq; then
    handle_error 4 "Failed to install jq"
fi

if [ "$MYOS" = "Ubuntu" ]; then
    log "INFO" "Setting up container runtime prerequisites..."
    
    # Configure kernel modules
    log "INFO" "Configuring kernel modules..."
    cat <<- EOF | sudo tee /etc/modules-load.d/containerd.conf > /dev/null || handle_error 5 "Failed to create modules config"
    overlay
    br_netfilter
EOF

    if ! sudo modprobe overlay || ! sudo modprobe br_netfilter; then
        handle_error 6 "Failed to load required kernel modules"
    fi

    # Configure sysctl parameters
    log "INFO" "Configuring system parameters..."
    cat <<- EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf > /dev/null || handle_error 7 "Failed to create sysctl config"
    net.bridge.bridge-nf-call-iptables  = 1
    net.ipv4.ip_forward                 = 1
    net.bridge.bridge-nf-call-ip6tables = 1
EOF

    if ! sudo sysctl --system; then
        handle_error 8 "Failed to apply sysctl parameters"
    fi

    # Install containerd
    log "INFO" "Installing containerd..."
    if ! sudo apt update || ! sudo apt install -y containerd; then
        handle_error 9 "Failed to install containerd"
    fi

    # Configure containerd
    log "INFO" "Configuring containerd..."
    sudo mkdir -p /etc/containerd
    cat <<- TOML | sudo tee /etc/containerd/config.toml > /dev/null || handle_error 10 "Failed to create containerd config"
version = 2
[plugins."io.containerd.grpc.v1.cri"]
  systemd_cgroup = true
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
    runtime_type = "io.containerd.runc.v2"
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
      SystemdCgroup = true
TOML

    # Restart and enable containerd
    log "INFO" "Starting containerd service..."
    if ! sudo systemctl restart containerd || ! sudo systemctl enable containerd; then
        handle_error 11 "Failed to start containerd service"
    fi

    # Verify containerd is running
    if ! systemctl is-active --quiet containerd; then
        handle_error 12 "containerd is not running. Check service status with: systemctl status containerd"
    fi

    # Verify configuration
    if ! grep -q "SystemdCgroup = true" /etc/containerd/config.toml; then
        handle_error 13 "Failed to verify containerd configuration"
    fi

    log "INFO" "✅ containerd installed and configured successfully with systemd cgroup driver"
else
    handle_error 14 "Unsupported operating system: ${MYOS}"
fi

# Disable AppArmor for runc if it exists
if [ -f /etc/apparmor.d/runc ]; then
    log "INFO" "Disabling AppArmor for runc..."
    sudo ln -s /etc/apparmor.d/runc /etc/apparmor.d/disable/ 2>/dev/null || true
    sudo apparmor_parser -R /etc/apparmor.d/runc 2>/dev/null || true
fi

# Create completion marker
touch /tmp/container.txt || handle_error 15 "Failed to create completion marker"
log "INFO" "Container runtime setup complete"
exit 0