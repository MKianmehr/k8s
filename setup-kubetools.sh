#!/usr/bin/env bash
set -e

# Professional kubeadm installation script for Ubuntu 20.04+ following Kubernetes upstream docs

# Ensure container runtime setup has completed
if [ ! -f /tmp/container.txt ]; then
	echo "ERROR: Container runtime not configured. Please run ./setup-container.sh first." >&2
	exit 1
fi

# Verify OS compatibility
if [ -f /etc/os-release ]; then
	. /etc/os-release
	if [ "$ID" != "ubuntu" ]; then
		echo "ERROR: Unsupported OS '$ID'. This script supports Ubuntu only." >&2
		exit 1
	fi
else
	echo "ERROR: Could not determine OS type. /etc/os-release not found." >&2
	exit 1
fi

# Load required kernel module for networking
sudo modprobe br_netfilter

# Add Kubernetes APT repository and key
sudo apt-get update
sudo apt-get install -y apt-transport-https curl

# Get the latest Kubernetes version
KUBEVERSION=$(curl -s https://api.github.com/repos/kubernetes/kubernetes/releases/latest | jq -r '.tag_name')
KUBEVERSION=${KUBEVERSION%.*}

# Add Kubernetes repository using the new format
curl -fsSL https://pkgs.k8s.io/core:/stable:/${KUBEVERSION}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBEVERSION}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

echo "Installing Kubernetes components version $KUBEVERSION"

# Install kubelet, kubeadm, kubectl
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl

# Prevent automatic updates of Kubernetes components
sudo apt-mark hold kubelet kubeadm kubectl

# Disable swap (required by kubelet)
sudo swapoff -a
sudo sed -i 's/\/swap/#\/swap/' /etc/fstab

# Configure crictl to talk to containerd
sudo crictl config --set runtime-endpoint=unix:///run/containerd/containerd.sock

# Summary and next steps
echo -e "
Kubernetes tools installed successfully (version $KUBEVERSION).

Next steps:
  1. Initialize the control plane:
       sudo kubeadm init --pod-network-cidr=<YOUR_POD_CIDR> ...

  2. Configure kubectl for your user:
       mkdir -p \$HOME/.kube
       sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config
       sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config

  3. Install a Pod network add-on (e.g., Calico):
       kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

  4. Join worker nodes using the provided 'kubeadm join' command.
"

