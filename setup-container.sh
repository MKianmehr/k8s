#!/bin/bash
# script that runs 
# https://kubernetes.io/docs/setup/production-environment/container-runtime

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

        # Configure containerd
        sudo mkdir -p /etc/containerd
        sudo containerd config default | sudo tee /etc/containerd/config.toml

        # Enable systemd cgroup driver
        sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

        # Restart containerd to apply changes
        sudo systemctl restart containerd

# We don't need to install runc separately, it's already included with containerd
# And we don't need to download the service file as it's included in the package

fi

sudo ln -s /etc/apparmor.d/runc /etc/apparmor.d/disable/ 2>/dev/null || true
sudo apparmor_parser -R /etc/apparmor.d/runc 2>/dev/null || true

touch /tmp/container.txt
exit