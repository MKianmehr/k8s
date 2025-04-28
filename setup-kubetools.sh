#!/bin/bash
# Kubernetes Tools Setup Script
# Author: System Administrator
# Version: 1.0
# License: MIT
# Description: Installs and configures Kubernetes tools (kubeadm, kubectl, kubelet)
# Usage: sudo ./setup-kubetools.sh

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

# Ensure container runtime setup has completed
if [ ! -f /tmp/container.txt ]; then
    handle_error 2 "Container runtime not configured. Please run ./setup-container.sh first."
fi

# Verify OS compatibility
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" != "ubuntu" ]; then
        handle_error 3 "Unsupported OS '$ID'. This script supports Ubuntu only."
    fi
else
    handle_error 4 "Could not determine OS type. /etc/os-release not found."
fi

# Load required kernel module for networking
log "INFO" "Loading required kernel modules..."
if ! sudo modprobe br_netfilter; then
    handle_error 5 "Failed to load br_netfilter kernel module"
fi

# Add Kubernetes APT repository and key
log "INFO" "Setting up Kubernetes repository..."
if ! sudo apt-get update || ! sudo apt-get install -y apt-transport-https curl; then
    handle_error 6 "Failed to install required packages"
fi

# Get the latest Kubernetes version
log "INFO" "Detecting latest Kubernetes version..."
KUBEVERSION=$(curl -s https://api.github.com/repos/kubernetes/kubernetes/releases/latest | jq -r '.tag_name') || handle_error 7 "Failed to detect Kubernetes version"
KUBEVERSION=${KUBEVERSION%.*}
log "INFO" "Detected Kubernetes version: ${KUBEVERSION}"

# Add Kubernetes repository
log "INFO" "Adding Kubernetes repository..."
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${KUBEVERSION}/deb/Release.key" | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg || handle_error 8 "Failed to add Kubernetes repository key"
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBEVERSION}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null || handle_error 9 "Failed to add Kubernetes repository"

# Install Kubernetes components
log "INFO" "Installing Kubernetes components..."
if ! sudo apt-get update || ! sudo apt-get install -y kubelet kubeadm kubectl; then
    handle_error 10 "Failed to install Kubernetes components"
fi

# Prevent automatic updates
log "INFO" "Preventing automatic updates of Kubernetes components..."
if ! sudo apt-mark hold kubelet kubeadm kubectl; then
    handle_error 11 "Failed to mark Kubernetes packages as held"
fi

# Disable swap
log "INFO" "Disabling swap..."
if ! sudo swapoff -a; then
    handle_error 12 "Failed to disable swap"
fi
if ! sudo sed -i 's/\/swap/#\/swap/' /etc/fstab; then
    handle_error 13 "Failed to comment out swap in /etc/fstab"
fi

# Configure crictl
log "INFO" "Configuring crictl..."
if ! sudo crictl config --set runtime-endpoint=unix:///run/containerd/containerd.sock; then
    handle_error 14 "Failed to configure crictl"
fi

# Print success message and next steps
log "INFO" "Kubernetes tools installed successfully (version ${KUBEVERSION})"
echo -e "\nNext steps:"
echo "  1. Initialize the control plane:"
echo "     sudo kubeadm init --pod-network-cidr=<YOUR_POD_CIDR> ..."
echo ""
echo "  2. Configure kubectl for your user:"
echo "     mkdir -p \$HOME/.kube"
echo "     sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config"
echo "     sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config"
echo ""
echo "  3. Install a Pod network add-on (e.g., Calico):"
echo "     kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml"
echo ""
echo "  4. Join worker nodes using the provided 'kubeadm join' command."
echo ""

exit 0

