#!/bin/bash
#
# Script to install and configure containerd as the container runtime
# for Kubernetes on Ubuntu systems (amd64 and arm64).
# Based on: https://kubernetes.io/docs/setup/production-environment/container-runtime
#
# Enhancements:
# - Added error handling (set -e, -u, -o pipefail)
# - Organized into functions
# - Added checks for dependencies and root privileges
# - Improved logging/feedback
# - Dynamic version fetching for containerd and runc
# - Cleanup of downloaded files
# - Explicit warning for AppArmor modification

# --- Configuration ---
# Set to 'true' to disable the runc AppArmor profile.
# WARNING: Disabling AppArmor reduces security constraints on containers.
# Only do this if absolutely necessary and understand the implications.
DISABLE_RUNC_APPARMOR="false"

# --- Script Setup ---
# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u
# Pipestatus: exit status of the last command that threw a non-zero exit status is returned.
set -o pipefail

# --- Helper Functions ---

# Log messages
log() {
  printf "[INFO] %s\n" "$@"
}

# Log errors
error() {
  printf "[ERROR] %s\n" "$@" >&2
  exit 1
}

# Check if running as root
check_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    error "This script must be run as root. Use sudo."
  fi
}

# Check for required commands
check_dependencies() {
  local deps=("awk" "hostnamectl" "curl" "jq" "tar" "tee" "modprobe" "sysctl" "wget" "install" "systemctl" "ln" "apparmor_parser" "cat" "mkdir")
  for cmd in "${deps[@]}"; do
    if ! command -v "${cmd}" &> /dev/null; then
      error "Required command '${cmd}' not found. Please install it."
    fi
  done
  log "All required commands are available."
}

# Detect OS and Architecture
detect_system() {
  log "Detecting Operating System and Architecture..."
  MYOS=$(hostnamectl | awk '/Operating System:/ { print $3 }')
  # OSVERSION=$(hostnamectl | awk '/Operating System:/ { print $4 }') # Not currently used

  if [[ -z "${MYOS}" ]]; then
      error "Could not determine Operating System using hostnamectl."
  fi

  ARCH=$(arch)
  case "${ARCH}" in
    aarch64) PLATFORM="arm64" ;;
    x86_64)  PLATFORM="amd64" ;;
    *)       error "Unsupported architecture: ${ARCH}" ;;
  esac
  log "Detected OS: ${MYOS}, Architecture: ${ARCH} (Platform: ${PLATFORM})"
}

# Configure kernel modules
setup_kernel_modules() {
  log "Configuring required kernel modules (overlay, br_netfilter)..."
  local modules_file="/etc/modules-load.d/containerd.conf"
  cat <<- EOF | sudo tee "${modules_file}" > /dev/null
	overlay
	br_netfilter
EOF
  log "Created ${modules_file} for persistent module loading."

  sudo modprobe overlay
  sudo modprobe br_netfilter
  log "Kernel modules loaded for the current session."
}

# Configure sysctl parameters
setup_sysctl() {
  log "Configuring required sysctl parameters for Kubernetes networking..."
  local sysctl_file="/etc/sysctl.d/99-kubernetes-cri.conf"
  cat <<- EOF | sudo tee "${sysctl_file}" > /dev/null
	net.bridge.bridge-nf-call-iptables  = 1
	net.ipv4.ip_forward                 = 1
	net.bridge.bridge-nf-call-ip6tables = 1
EOF
  log "Created ${sysctl_file} for persistent sysctl settings."

  # Apply sysctl params without reboot
  sudo sysctl --system
  log "Applied sysctl settings for the current session."
}

# Install containerd
install_containerd() {
  log "Installing containerd..."
  local latest_version_url="https://api.github.com/repos/containerd/containerd/releases/latest"
  local containerd_version runc_version containerd_tarball runc_binary

  log "Fetching latest containerd version..."
  containerd_version=$(curl -fsSL "${latest_version_url}" | jq -r '.tag_name')
  if [[ -z "${containerd_version}" ]]; then
      error "Failed to fetch latest containerd version tag from GitHub API."
  fi
  containerd_version=${containerd_version#v} # Remove leading 'v'
  log "Latest containerd version: ${containerd_version}"

  containerd_tarball="containerd-${containerd_version}-linux-${PLATFORM}.tar.gz"
  local download_url="https://github.com/containerd/containerd/releases/download/v${containerd_version}/${containerd_tarball}"

  log "Downloading containerd v${containerd_version} for ${PLATFORM}..."
  wget -q --show-progress "${download_url}" -O "${containerd_tarball}"
  if [[ $? -ne 0 ]]; then
      error "Failed to download containerd tarball from ${download_url}"
  fi

  log "Extracting containerd binaries to /usr/local..."
  # Note: This step might not be fully idempotent if files already exist.
  sudo tar xvf "${containerd_tarball}" -C /usr/local
  log "Containerd extracted."

  # Cleanup downloaded tarball
  rm -f "${containerd_tarball}"
}

# Configure containerd
configure_containerd() {
  log "Configuring containerd..."
  local config_dir="/etc/containerd"
  local config_file="${config_dir}/config.toml"

  sudo mkdir -p "${config_dir}"
  log "Ensured configuration directory exists: ${config_dir}"

  log "Creating containerd configuration file: ${config_file}"
  # Note: This will overwrite existing config.toml. Backup if needed.
  cat <<- TOML | sudo tee "${config_file}" > /dev/null
version = 2
[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    [plugins."io.containerd.grpc.v1.cri".containerd]
      # discard_unpacked_layers = true # Optional: Consider if disk space is critical
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            # Ensure Kubelet is also configured with 'systemd' cgroup driver
            SystemdCgroup = true
TOML
  log "Containerd configuration written with SystemdCgroup enabled."
}

# Install runc
install_runc() {
  log "Installing runc..."
  local latest_version_url="https://api.github.com/repos/opencontainers/runc/releases/latest"
  local runc_version runc_binary

  log "Fetching latest runc version..."
  runc_version=$(curl -fsSL "${latest_version_url}" | jq -r '.tag_name')
   if [[ -z "${runc_version}" ]]; then
      error "Failed to fetch latest runc version tag from GitHub API."
  fi
  log "Latest runc version: ${runc_version}"

  runc_binary="runc.${PLATFORM}"
  local download_url="https://github.com/opencontainers/runc/releases/download/${runc_version}/${runc_binary}"

  log "Downloading runc ${runc_version} for ${PLATFORM}..."
  wget -q --show-progress "${download_url}" -O "${runc_binary}"
   if [[ $? -ne 0 ]]; then
      error "Failed to download runc binary from ${download_url}"
  fi

  log "Installing runc binary to /usr/local/sbin/runc..."
  # Note: This will overwrite existing runc binary.
  sudo install -m 755 "${runc_binary}" /usr/local/sbin/runc
  log "Runc installed."

  # Cleanup downloaded binary
  rm -f "${runc_binary}"
}

# Setup containerd systemd service
setup_containerd_service() {
  log "Setting up systemd service for containerd..."
  local service_url="https://raw.githubusercontent.com/containerd/containerd/main/containerd.service"
  local service_file_name="containerd.service"
  # Standard location might vary slightly, /usr/lib/systemd/system is common
  local systemd_path="/usr/lib/systemd/system"

  # Ensure the systemd directory exists (though it usually does)
  sudo mkdir -p "${systemd_path}"

  log "Downloading containerd.service file..."
  wget -q --show-progress "${service_url}" -O "${service_file_name}"
  if [[ $? -ne 0 ]]; then
      error "Failed to download containerd.service from ${service_url}"
  fi

  log "Moving service file to ${systemd_path}..."
  # Note: This will overwrite existing service file.
  sudo mv "${service_file_name}" "${systemd_path}/"

  log "Reloading systemd daemon, enabling and starting containerd service..."
  sudo systemctl daemon-reload
  sudo systemctl enable --now containerd

  # Check service status
  if systemctl is-active --quiet containerd; then
    log "Containerd service is active."
  else
    error "Containerd service failed to start. Check logs with 'journalctl -u containerd'."
  fi
}

# Optionally disable runc AppArmor profile
manage_runc_apparmor() {
  if [[ "${DISABLE_RUNC_APPARMOR}" != "true" ]]; then
    log "Skipping AppArmor profile modification for runc."
    return
  fi

  log "WARNING: Disabling runc AppArmor profile as requested. This reduces container security."
  local runc_profile="/etc/apparmor.d/runc"
  local disable_dir="/etc/apparmor.d/disable"

  if [[ -f "${runc_profile}" ]]; then
    sudo mkdir -p "${disable_dir}"
    if [[ ! -L "${disable_dir}/runc" ]]; then
        log "Linking ${runc_profile} to ${disable_dir}/ to disable on next load."
        sudo ln -s "${runc_profile}" "${disable_dir}/"
    else
        log "Runc profile already linked in disable directory."
    fi
    log "Removing currently loaded runc profile from kernel..."
    # Use -R flag to remove the profile if loaded. Ignore error if not loaded.
    sudo apparmor_parser -R "${runc_profile}" || true
    log "Runc AppArmor profile disabled."
  else
    log "Runc AppArmor profile (${runc_profile}) not found. Skipping disable step."
  fi
}

# --- Main Execution ---
main() {
  check_root
  check_dependencies
  detect_system

  if [[ "${MYOS}" != "Ubuntu" ]]; then
    error "This script is designed for Ubuntu. Detected OS: ${MYOS}. Aborting."
  fi

  log "Starting Kubernetes container runtime setup for Ubuntu ${PLATFORM}..."

  # Install jq first as it's needed for version fetching
  log "Ensuring jq is installed..."
  if ! command -v jq &> /dev/null; then
      sudo apt-get update -y
      sudo apt-get install -y jq
  else
      log "jq is already installed."
  fi


  setup_kernel_modules
  setup_sysctl
  install_containerd
  configure_containerd
  install_runc
  setup_containerd_service
  manage_runc_apparmor

  # Create a more informative marker file
  local marker_file="/tmp/containerd_setup_complete.txt"
  printf "Containerd setup completed successfully on %s\n" "$(date)" | sudo tee "${marker_file}" > /dev/null
  log "Setup complete. Marker file created at ${marker_file}"
  log "System is now prepared for Kubernetes components (kubelet, kubeadm, kubectl)."
}

# Run the main function
main

exit 0
