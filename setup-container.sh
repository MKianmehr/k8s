#!/bin/bash
# script that runs 
# https://kubernetes.io/docs/setup/production-environment/container-runtime

set -e

# changes March 14 2023: introduced $PLATFORM to have this work on amd64 as well as arm64

# setting MYOS variable
MYOS=$(hostnamectl | awk '/Operating/ { print $3 }')
OSVERSION=$(hostnamectl | awk '/Operating/ { print $4 }')
# beta: building in ARM support
[ $(arch) = aarch64 ] && PLATFORM=arm64
[ $(arch) = x86_64 ] && PLATFORM=amd64

sudo apt install -y jq

if [ $MYOS = "Ubuntu" ]
then
	### setting up container runtime prereq
	cat <<- EOF | sudo tee /etc/modules-load.d/containerd.conf
	overlay
	br_netfilter
EOF

	sudo modprobe overlay
	sudo modprobe br_netfilter

        # Setup required sysctl params, these persist across reboots.
        cat <<- EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
        net.bridge.bridge-nf-call-iptables  = 1
        net.ipv4.ip_forward                 = 1
        net.bridge.bridge-nf-call-ip6tables = 1
EOF

        # Apply sysctl params without reboot
        sudo sysctl --system

        # Install containerd directly from Ubuntu repos
        sudo apt update
        sudo apt install -y containerd

        # Configure containerd with systemd cgroup driver enabled
        sudo mkdir -p /etc/containerd
        cat <<- TOML | sudo tee /etc/containerd/config.toml
version = 2
[plugins."io.containerd.grpc.v1.cri"]
  systemd_cgroup = true
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
    runtime_type = "io.containerd.runc.v2"
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
      SystemdCgroup = true
TOML
        
        # Restart containerd to apply changes
        sudo systemctl restart containerd
        sudo systemctl enable containerd

        # Verify containerd is running
        if ! systemctl is-active --quiet containerd; then
            echo "ERROR: containerd is not running. Check service status with: systemctl status containerd"
            exit 1
        fi
        
        # Verify the configuration
        if ! grep -q "SystemdCgroup = true" /etc/containerd/config.toml; then
            echo "ERROR: Failed to set SystemdCgroup = true"
            exit 1
        fi
        
        echo "✅ containerd installed and configured successfully with systemd cgroup driver"
fi

# Disable AppArmor for runc if it exists
if [ -f /etc/apparmor.d/runc ]; then
    sudo ln -s /etc/apparmor.d/runc /etc/apparmor.d/disable/ 2>/dev/null || true
    sudo apparmor_parser -R /etc/apparmor.d/runc 2>/dev/null || true
fi

touch /tmp/container.txt
echo "container runtime setup complete"
exit 0