#!/bin/bash
# kubeadm installation instructions as on
# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/

# this script supports Ubuntu 20.04 LTS and later only
# run this script with sudo

if ! [ -f /tmp/container.txt ]
then
	echo "ERROR: Container runtime not configured. Please run ./setup-container.sh first." >&2
	exit 1
fi

# setting MYOS variable
MYOS=$(hostnamectl | awk '/Operating/ { print $3 }')
OSVERSION=$(hostnamectl | awk '/Operating/ { print $4 }')

# detecting latest Kubernetes version
KUBEVERSION=$(curl -s https://api.github.com/repos/kubernetes/kubernetes/releases/latest | jq -r '.tag_name')
KUBEVERSION=${KUBEVERSION%.*}

if [ "$MYOS" = "Ubuntu" ]
then
	echo "RUNNING UBUNTU CONFIG"
	cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF
	
	sudo apt-get update && sudo apt-get install -y apt-transport-https curl
	curl -fsSL https://pkgs.k8s.io/core:/stable:/${KUBEVERSION}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
	echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBEVERSION}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
	sleep 2

	sudo apt-get update
	sudo apt-get install -y kubelet kubeadm kubectl
	sudo apt-mark hold kubelet kubeadm kubectl
	sudo swapoff -a
	
	sudo sed -i 's/\/swap/#\/swap/' /etc/fstab
fi

sudo crictl config --set runtime-endpoint=unix:///run/containerd/containerd.sock

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

