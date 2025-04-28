# Kubernetes Cluster Bootstrap Scripts

This directory contains two scripts to automate the bootstrapping of a Kubernetes cluster on Ubuntu 20.04+:

- **setup-container.sh**: Installs and configures Containerd as the CRI runtime.
- **setup-kubetools.sh**: Installs Kubernetes command-line tools (`kubelet`, `kubeadm`, `kubectl`) and prepares the node for cluster initialization.

---

## Prerequisites

- Ubuntu 20.04 LTS or later.
- `sudo` or root privileges.
- Internet connectivity.

Each script enforces preconditions and exits with an error if requirements are not met.

---

## 1. setup-container.sh

Installs Containerd via the official `containerd.io` package, applies the default configuration, enables the `systemd` cgroup driver, and restarts the service.

Usage:

```bash
sudo chmod +x setup-container.sh
sudo ./setup-container.sh
```

This script will:

1. Load the required kernel modules (`overlay`, `br_netfilter`).
2. Configure persistent `sysctl` settings for bridged networking and IP forwarding.
3. Install `containerd.io` from the Ubuntu repositories.
4. Generate `/etc/containerd/config.toml` and enable `SystemdCgroup = true`.
5. Restart the `containerd` systemd service.

Upon success, it writes `/tmp/container.txt` as a flag file.

---

## 2. setup-kubetools.sh

Installs and pins the Kubernetes components (`kubelet`, `kubeadm`, `kubectl`) to the latest stable release.

Usage:

```bash
sudo chmod +x setup-kubetools.sh
sudo ./setup-kubetools.sh
```

This script will:

1. Verify that containerd setup completed (`/tmp/container.txt`).
2. Add the official Kubernetes APT repository and GPG key.
3. Fetch the latest GitHub release tag and install `kubelet`, `kubeadm`, and `kubectl` (`version-00`).
4. Hold the packages to prevent unintended upgrades.
5. Disable swap (required by `kubelet`).
6. Configure `crictl` to talk to Containerd's socket.

---

## Next Steps

Once both scripts succeed, proceed to initialize and join the cluster:

1. **Initialize control-plane node** (on master):

   ```bash
   sudo kubeadm init
   ```

2. **Configure kubectl for your user**:

   ```bash
   mkdir -p $HOME/.kube
   sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
   sudo chown $(id -u):$(id -g) $HOME/.kube/config
   ```

3. **Check kube-system pods**:

   ```bash
   kubectl get pods -n kube-system
   ```

   We will see sth like:

   ```bash
   ubuntu@master1:~$ kubectl get pods -n kube-system
    NAME                              READY   STATUS    RESTARTS   AGE
    coredns-674b8bbfcf-bz48n          0/1     Pending   0          22m
    coredns-674b8bbfcf-s8trm          0/1     Pending   0          22m
    etcd-master1                      1/1     Running   0          22m
    kube-apiserver-master1            1/1     Running   0          22m
    kube-controller-manager-master1   1/1     Running   0          22m
    kube-proxy-cn9lm                  1/1     Running   0          22m
    kube-scheduler-master1            1/1     Running   0          22m
    ubuntu@master1:~$
   ```

   which says coredns is in pending state

4. **Install a Pod network add-on** (e.g., Calico):

   ```bash
   kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
   ```

5. **Join workers** (on each worker node):

   ```bash
   sudo kubeadm join <MASTER_IP>:<PORT> \
     --token <TOKEN> \
     --discovery-token-ca-cert-hash sha256:<HASH>
   ```

---

## License

These scripts are provided under the MIT License. See [LICENSE](LICENSE) for details.
