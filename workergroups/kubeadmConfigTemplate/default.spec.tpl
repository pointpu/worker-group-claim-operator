{{- define "workergroups.kubeadmConfigTemplate.spec.default" -}}
  {{- printf `
files:
  - content: |
      version = 2       
      [plugins]
        [plugins."io.containerd.grpc.v1.cri"]
          sandbox_image = "registry.k8s.io/pause:3.9"
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v2"
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
          SystemdCgroup = true
        [plugins."io.containerd.grpc.v1.cri".registry]
          config_path = "/etc/containerd/certs.d/"
    owner: root:root
    path: /etc/containerd/conf.d/b-cloud.toml
    permissions: "0644"
  - content: |
      version = 2
      imports = ["/etc/containerd/conf.d/*.toml"]
    owner: root:root
    path: /etc/containerd/config.toml
    permissions: "0644"
  - content: >
      #!/bin/bash

      set -Eeuo pipefail

      COMPONENT_VERSION="${COMPONENT_VERSION:-1.7.19}"

      REPOSITORY="${REPOSITORY:-https://github.com/containerd/containerd/releases/download}"

      PATH_BIN="${REPOSITORY}/v${COMPONENT_VERSION}/containerd-${COMPONENT_VERSION}-linux-amd64.tar.gz"

      PATH_SHA256="${REPOSITORY}/v${COMPONENT_VERSION}/containerd-${COMPONENT_VERSION}-linux-amd64.tar.gz.sha256sum"

      INSTALL_PATH="/usr/local/bin/"

      LOG_TAG="containerd-installer"

      TMP_DIR="$(mktemp -d)"

      logger -t "$LOG_TAG" "[INFO] Checking current containerd version..."

      CURRENT_VERSION=$($INSTALL_PATH/containerd --version 2>/dev/null | awk
      '{print $3}' | sed 's/v//') || CURRENT_VERSION="none"

      COMPONENT_VERSION_CLEAN=$(echo "$COMPONENT_VERSION" | sed 's/^v//')

      logger -t "$LOG_TAG" "[INFO] Current: $CURRENT_VERSION, Target:
      $COMPONENT_VERSION_CLEAN"


      if [[ "$CURRENT_VERSION" != "$COMPONENT_VERSION_CLEAN" ]]; then
        logger -t "$LOG_TAG" "[INFO] Download URL: $PATH_BIN"
        logger -t "$LOG_TAG" "[INFO] Updating containerd to version $COMPONENT_VERSION_CLEAN..."

        cd "$TMP_DIR"
        logger -t "$LOG_TAG" "[INFO] Working directory: $PWD"

        logger -t "$LOG_TAG" "[INFO] Downloading containerd..."
        curl -fsSL -o "containerd-${COMPONENT_VERSION}-linux-amd64.tar.gz" "$PATH_BIN" || { logger -t "$LOG_TAG" "[ERROR] Failed to download containerd"; exit 1; }

        logger -t "$LOG_TAG" "[INFO] Downloading checksum file..."
        curl -fsSL -o "containerd.sha256sum" "$PATH_SHA256" || { logger -t "$LOG_TAG" "[ERROR] Failed to download checksum file"; exit 1; }

        logger -t "$LOG_TAG" "[INFO] Verifying checksum..."
        sha256sum -c containerd.sha256sum | grep 'OK' || { logger -t "$LOG_TAG" "[ERROR] Checksum verification failed!"; exit 1; }

        logger -t "$LOG_TAG" "[INFO] Extracting files..."
        tar -C "$TMP_DIR" -xvf "containerd-${COMPONENT_VERSION}-linux-amd64.tar.gz"

        logger -t "$LOG_TAG" "[INFO] Installing binaries..."
        install -m 755 "$TMP_DIR/bin/containerd" $INSTALL_PATH
        install -m 755 "$TMP_DIR/bin/containerd-shim"* $INSTALL_PATH
        install -m 755 "$TMP_DIR/bin/ctr" $INSTALL_PATH

        logger -t "$LOG_TAG" "[INFO] Containerd successfully updated to $COMPONENT_VERSION_CLEAN."
        rm -rf "$TMP_DIR"

      else
        logger -t "$LOG_TAG" "[INFO] Containerd is already up to date. Skipping installation."
      fi
    owner: root:root
    path: /etc/default/containerd/download-script.sh
    permissions: "0755"
  - content: |
      COMPONENT_VERSION="{{ .containerdVer }}"
      REPOSITORY="https://github.com/containerd/containerd/releases/download"
    owner: root:root
    path: /etc/default/containerd/download.env
    permissions: "0644"
  - content: |
      [Unit]
      Description=Install and update b-cloud component containerd
      After=network.target
      Wants=network-online.target

      [Service]
      Type=oneshot
      EnvironmentFile=-/etc/default/containerd/download.env
      ExecStart=/bin/bash -c "/etc/default/containerd/download-script.sh"
      RemainAfterExit=yes

      [Install]
      WantedBy=multi-user.target
    owner: root:root
    path: /usr/lib/systemd/system/containerd-install.service
    permissions: "0644"
  - content: |
      [Unit]
      Description=containerd container runtime
      Documentation=https://containerd.io
      After=network.target local-fs.target containerd-install.service runc-install.service
      Wants=containerd-install.service runc-install.service

      [Service]
      ExecStartPre=-/sbin/modprobe overlay
      ExecStart=/usr/local/bin/containerd

      Type=notify
      Delegate=yes
      KillMode=process
      Restart=always
      RestartSec=5
      LimitNPROC=infinity
      LimitCORE=infinity
      LimitNOFILE=infinity
      TasksMax=infinity
      OOMScoreAdjust=-999

      [Install]
      WantedBy=multi-user.target
    owner: root:root
    path: /usr/lib/systemd/system/containerd.service
    permissions: "0644"
  - content: >
      #!/bin/bash

      set -Eeuo pipefail

      COMPONENT_VERSION="${COMPONENT_VERSION:-v1.1.12}"

      REPOSITORY="${REPOSITORY:-https://github.com/opencontainers/runc/releases/download}"

      PATH_BIN="${REPOSITORY}/${COMPONENT_VERSION}/runc.amd64"

      PATH_SHA256="${REPOSITORY}/${COMPONENT_VERSION}/runc.sha256sum"

      INSTALL_PATH="/usr/local/bin/runc"

      LOG_TAG="runc-installer"

      TMP_DIR="$(mktemp -d)"

      logger -t "$LOG_TAG" "[INFO] Checking current runc version..."

      CURRENT_VERSION=$($INSTALL_PATH --version 2>/dev/null | head -n1 | awk '{print $NF}') || CURRENT_VERSION="none"

      COMPONENT_VERSION_CLEAN=$(echo "$COMPONENT_VERSION" | sed 's/^v//')

      logger -t "$LOG_TAG" "[INFO] Current: $CURRENT_VERSION, Target: $COMPONENT_VERSION_CLEAN"


      if [[ "$CURRENT_VERSION" != "$COMPONENT_VERSION_CLEAN" ]]; then
        logger -t "$LOG_TAG" "[INFO] Download URL: $PATH_BIN"
        logger -t "$LOG_TAG" "[INFO] Updating runc to version $COMPONENT_VERSION..."

        cd "$TMP_DIR"
        logger -t "$LOG_TAG" "[INFO] Working directory: $PWD"

        logger -t "$LOG_TAG" "[INFO] Downloading runc..."
        curl -fsSL -o runc.amd64 "$PATH_BIN" || { logger -t "$LOG_TAG" "[ERROR] Failed to download runc"; exit 1; }

        logger -t "$LOG_TAG" "[INFO] Downloading checksum file..."
        curl -fsSL -o runc.sha256sum "$PATH_SHA256" || { logger -t "$LOG_TAG" "[ERROR] Failed to download checksum file"; exit 1; }

        logger -t "$LOG_TAG" "[INFO] Verifying checksum..."
        grep "runc.amd64" runc.sha256sum | sha256sum -c - || { logger -t "$LOG_TAG" "[ERROR] Checksum verification failed!"; exit 1; }

        logger -t "$LOG_TAG" "[INFO] Installing runc..."
        install -m 755 runc.amd64 "$INSTALL_PATH"

        logger -t "$LOG_TAG" "[INFO] runc successfully updated to $COMPONENT_VERSION."
        rm -rf "$TMP_DIR"

      else
        logger -t "$LOG_TAG" "[INFO] runc is already up to date. Skipping installation."
      fi
    owner: root:root
    path: /etc/default/runc/download-script.sh
    permissions: "0755"
  - content: |
      COMPONENT_VERSION="{{ .runcVer }}"
      REPOSITORY="https://github.com/opencontainers/runc/releases/download"
    owner: root:root
    path: /etc/default/runc/download.env
    permissions: "0644"
  - content: |
      [Unit]
      Description=Install and update b-cloud component runc
      After=network.target
      Wants=network-online.target

      [Service]
      Type=oneshot
      EnvironmentFile=-/etc/default/runc/download.env
      ExecStart=/bin/bash -c "/etc/default/runc/download-script.sh"
      RemainAfterExit=yes

      [Install]
      WantedBy=multi-user.target
    owner: root:root
    path: /usr/lib/systemd/system/runc-install.service
    permissions: "0644"
  - content: >
      #!/bin/bash

      set -Eeuo pipefail


      COMPONENT_VERSION="${COMPONENT_VERSION:-v1.30.0}"

      REPOSITORY="${REPOSITORY:-https://github.com/kubernetes-sigs/cri-tools/releases/download}"

      PATH_BIN="${REPOSITORY}/${COMPONENT_VERSION}/crictl-${COMPONENT_VERSION}-linux-amd64.tar.gz"

      PATH_SHA256="${REPOSITORY}/${COMPONENT_VERSION}/crictl-${COMPONENT_VERSION}-linux-amd64.tar.gz.sha256"

      INSTALL_PATH="/usr/local/bin/crictl"

      LOG_TAG="crictl-installer"

      TMP_DIR="$(mktemp -d)"

      logger -t "$LOG_TAG" "[INFO] Checking current crictl version..."

      CURRENT_VERSION=$($INSTALL_PATH --version 2>/dev/null | awk '{print $3}'
      | sed 's/v//') || CURRENT_VERSION="none"

      COMPONENT_VERSION_CLEAN=$(echo "$COMPONENT_VERSION" | sed 's/^v//')

      logger -t "$LOG_TAG" "[INFO] Current: $CURRENT_VERSION, Target:
      $COMPONENT_VERSION_CLEAN"


      if [[ "$CURRENT_VERSION" != "$COMPONENT_VERSION_CLEAN" ]]; then
        logger -t "$LOG_TAG" "[INFO] Download URL: $PATH_BIN"
        logger -t "$LOG_TAG" "[INFO] Updating crictl to version $COMPONENT_VERSION_CLEAN..."
        
        cd "$TMP_DIR"
        logger -t "$LOG_TAG" "[INFO] Working directory: $PWD"
        
        logger -t "$LOG_TAG" "[INFO] Downloading crictl..."
        curl -fsSL -o crictl.tar.gz "$PATH_BIN" || { logger -t "$LOG_TAG" "[ERROR] Failed to download crictl"; exit 1; }
        
        logger -t "$LOG_TAG" "[INFO] Downloading checksum file..."
        curl -fsSL -o crictl.sha256sum "$PATH_SHA256" || { logger -t "$LOG_TAG" "[ERROR] Failed to download checksum file"; exit 1; }
        
        logger -t "$LOG_TAG" "[INFO] Verifying checksum..."
        awk '{print $1"  crictl.tar.gz"}' crictl.sha256sum | sha256sum -c - || { logger -t "$LOG_TAG" "[ERROR] Checksum verification failed!"; exit 1; }
        
        logger -t "$LOG_TAG" "[INFO] Extracting files..."
        tar -C "$TMP_DIR" -xvf crictl.tar.gz
        
        logger -t "$LOG_TAG" "[INFO] Installing crictl..."
        install -m 755 "$TMP_DIR/crictl" "$INSTALL_PATH"
        
        logger -t "$LOG_TAG" "[INFO] crictl successfully updated to $COMPONENT_VERSION_CLEAN."
        rm -rf "$TMP_DIR"

      else
        logger -t "$LOG_TAG" "[INFO] crictl is already up to date. Skipping installation."
      fi
    owner: root:root
    path: /etc/default/crictl/download-script.sh
    permissions: "0755"
  - content: |
      COMPONENT_VERSION="{{ .crictlVer }}"
      REPOSITORY="https://github.com/kubernetes-sigs/cri-tools/releases/download"
    owner: root:root
    path: /etc/default/crictl/download.env
    permissions: "0644"
  - content: |
      [Unit]
      Description=Install and update b-cloud component crictl
      After=network.target
      Wants=network-online.target

      [Service]
      Type=oneshot
      EnvironmentFile=-/etc/default/crictl/download.env
      ExecStart=/bin/bash -c "/etc/default/crictl/download-script.sh"
      RemainAfterExit=yes

      [Install]
      WantedBy=multi-user.target
    owner: root:root
    path: /usr/lib/systemd/system/crictl-install.service
    permissions: "0644"
  - content: |
      runtime-endpoint: unix:///var/run/containerd/containerd.sock
    owner: root:root
    path: /etc/crictl.yaml
    permissions: "0644"
  - content: >
      #!/bin/bash

      set -Eeuo pipefail

      COMPONENT_VERSION="${COMPONENT_VERSION:-v1.30.4}"

      REPOSITORY="${REPOSITORY:-https://dl.k8s.io}"

      PATH_BIN="${REPOSITORY}/${COMPONENT_VERSION}/bin/linux/amd64/kubeadm"

      PATH_SHA256="${REPOSITORY}/${COMPONENT_VERSION}/bin/linux/amd64/kubeadm.sha256"

      INSTALL_PATH="/usr/local/bin/kubeadm"

      LOG_TAG="kubeadm-installer"

      TMP_DIR="$(mktemp -d)"

      logger -t "$LOG_TAG" "[INFO] Checking current kubeadm version..."

      CURRENT_VERSION=$($INSTALL_PATH version -o json 2>/dev/null | jq -r
      '.clientVersion.gitVersion' | sed 's/^v//') || CURRENT_VERSION="none"

      COMPONENT_VERSION_CLEAN=$(echo "$COMPONENT_VERSION" | sed 's/^v//')

      logger -t "$LOG_TAG" "[INFO] Current: $CURRENT_VERSION, Target:
      $COMPONENT_VERSION_CLEAN"


      if [[ "$CURRENT_VERSION" != "$COMPONENT_VERSION_CLEAN" ]]; then
        logger -t "$LOG_TAG" "[INFO] Download URL: $PATH_BIN"
        logger -t "$LOG_TAG" "[INFO] Updating kubeadm to version $COMPONENT_VERSION_CLEAN..."
        
        cd "$TMP_DIR"
        logger -t "$LOG_TAG" "[INFO] Working directory: $PWD"
        
        logger -t "$LOG_TAG" "[INFO] Downloading kubeadm..."
        curl -fsSL -o kubeadm "$PATH_BIN" || { logger -t "$LOG_TAG" "[ERROR] Failed to download kubeadm"; exit 1; }
        
        logger -t "$LOG_TAG" "[INFO] Downloading checksum file..."
        curl -fsSL -o kubeadm.sha256sum "$PATH_SHA256" || { logger -t "$LOG_TAG" "[ERROR] Failed to download checksum file"; exit 1; }
        
        logger -t "$LOG_TAG" "[INFO] Verifying checksum..."
        awk '{print $1"  kubeadm"}' kubeadm.sha256sum | sha256sum -c - || { logger -t "$LOG_TAG" "[ERROR] Checksum verification failed!"; exit 1; }
        
        logger -t "$LOG_TAG" "[INFO] Installing kubeadm..."
        install -m 755 kubeadm "$INSTALL_PATH"
        
        logger -t "$LOG_TAG" "[INFO] kubeadm successfully updated to $COMPONENT_VERSION_CLEAN."
        rm -rf "$TMP_DIR"

      else
        logger -t "$LOG_TAG" "[INFO] kubeadm is already up to date. Skipping installation."
      fi
    owner: root:root
    path: /etc/default/kubeadm/download-script.sh
    permissions: "0755"
  - content: |
      COMPONENT_VERSION="{{ .kubeadmVer }}"
      REPOSITORY="https://dl.k8s.io"
    owner: root:root
    path: /etc/default/kubeadm/download.env
    permissions: "0644"
  - content: |
      [Unit]
      Description=Install and update kubeadm
      After=network.target
      Wants=network-online.target

      [Service]
      Type=oneshot
      EnvironmentFile=-/etc/default/kubeadm/download.env
      ExecStart=/bin/bash -c "/etc/default/kubeadm/download-script.sh"
      RemainAfterExit=yes

      [Install]
      WantedBy=multi-user.target
    owner: root:root
    path: /usr/lib/systemd/system/kubeadm-install.service
    permissions: "0644"
  - content: >
      #!/bin/bash

      set -Eeuo pipefail

      COMPONENT_VERSION="${COMPONENT_VERSION:-v1.30.4}"

      REPOSITORY="${REPOSITORY:-https://dl.k8s.io}"

      PATH_BIN="${REPOSITORY}/${COMPONENT_VERSION}/bin/linux/amd64/kubectl"

      PATH_SHA256="${REPOSITORY}/${COMPONENT_VERSION}/bin/linux/amd64/kubectl.sha256"

      INSTALL_PATH="/usr/local/bin/kubectl"

      LOG_TAG="kubectl-installer"

      TMP_DIR="$(mktemp -d)"

      logger -t "$LOG_TAG" "[INFO] Checking current kubectl version..."

      CURRENT_VERSION=$($INSTALL_PATH version -o json --client=true
      2>/dev/null | jq -r '.clientVersion.gitVersion' | sed 's/^v//') ||
      CURRENT_VERSION="none"

      COMPONENT_VERSION_CLEAN=$(echo "$COMPONENT_VERSION" | sed 's/^v//')

      logger -t "$LOG_TAG" "[INFO] Current: $CURRENT_VERSION, Target:
      $COMPONENT_VERSION_CLEAN"


      if [[ "$CURRENT_VERSION" != "$COMPONENT_VERSION_CLEAN" ]]; then
        logger -t "$LOG_TAG" "[INFO] Download URL: $PATH_BIN"
        logger -t "$LOG_TAG" "[INFO] Updating kubectl to version $COMPONENT_VERSION_CLEAN..."
        
        cd "$TMP_DIR"
        logger -t "$LOG_TAG" "[INFO] Working directory: $PWD"
        
        logger -t "$LOG_TAG" "[INFO] Downloading kubectl..."
        curl -fsSL -o kubectl "$PATH_BIN" || { logger -t "$LOG_TAG" "[ERROR] Failed to download kubectl"; exit 1; }
        
        logger -t "$LOG_TAG" "[INFO] Downloading checksum file..."
        curl -fsSL -o kubectl.sha256sum "$PATH_SHA256" || { logger -t "$LOG_TAG" "[ERROR] Failed to download checksum file"; exit 1; }
        
        logger -t "$LOG_TAG" "[INFO] Verifying checksum..."
        awk '{print $1"  kubectl"}' kubectl.sha256sum | sha256sum -c - || { logger -t "$LOG_TAG" "[ERROR] Checksum verification failed!"; exit 1; }
        
        logger -t "$LOG_TAG" "[INFO] Installing kubectl..."
        install -m 755 kubectl "$INSTALL_PATH"
        
        logger -t "$LOG_TAG" "[INFO] kubectl successfully updated to $COMPONENT_VERSION_CLEAN."
        rm -rf "$TMP_DIR"

      else
        logger -t "$LOG_TAG" "[INFO] kubectl is already up to date. Skipping installation."
      fi
    owner: root:root
    path: /etc/default/kubectl/download-script.sh
    permissions: "0755"
  - content: |
      COMPONENT_VERSION="{{ .kubectlVer }}"
      REPOSITORY="https://dl.k8s.io"
    owner: root:root
    path: /etc/default/kubectl/download.env
    permissions: "0644"
  - content: |
      [Unit]
      Description=Install and update kubectl
      After=network.target
      Wants=network-online.target

      [Service]
      Type=oneshot
      EnvironmentFile=-/etc/default/kubectl/download.env
      ExecStart=/bin/bash -c "/etc/default/kubectl/download-script.sh"
      RemainAfterExit=yes

      [Install]
      WantedBy=multi-user.target
    owner: root:root
    path: /usr/lib/systemd/system/kubectl-install.service
    permissions: "0644"
  - content: >
      #!/bin/bash

      set -Eeuo pipefail

      COMPONENT_VERSION="${COMPONENT_VERSION:-v1.30.4}"

      REPOSITORY="${REPOSITORY:-https://dl.k8s.io}"

      PATH_BIN="${REPOSITORY}/${COMPONENT_VERSION}/bin/linux/amd64/kubelet"

      PATH_SHA256="${REPOSITORY}/${COMPONENT_VERSION}/bin/linux/amd64/kubelet.sha256"

      INSTALL_PATH="/usr/local/bin/kubelet"

      LOG_TAG="kubelet-installer"

      TMP_DIR="$(mktemp -d)"

      logger -t "$LOG_TAG" "[INFO] Checking current kubelet version..."

      CURRENT_VERSION=$($INSTALL_PATH --version 2>/dev/null | awk '{print $2}'
      | sed 's/v//') || CURRENT_VERSION="none"

      COMPONENT_VERSION_CLEAN=$(echo "$COMPONENT_VERSION" | sed 's/^v//')

      logger -t "$LOG_TAG" "[INFO] Current: $CURRENT_VERSION, Target:
      $COMPONENT_VERSION_CLEAN"


      if [[ "$CURRENT_VERSION" != "$COMPONENT_VERSION_CLEAN" ]]; then
        logger -t "$LOG_TAG" "[INFO] Download URL: $PATH_BIN"
        logger -t "$LOG_TAG" "[INFO] Updating kubelet to version $COMPONENT_VERSION_CLEAN..."
        
        cd "$TMP_DIR"
        logger -t "$LOG_TAG" "[INFO] Working directory: $PWD"
        
        logger -t "$LOG_TAG" "[INFO] Downloading kubelet..."
        curl -fsSL -o kubelet "$PATH_BIN" || { logger -t "$LOG_TAG" "[ERROR] Failed to download kubelet"; exit 1; }
        
        logger -t "$LOG_TAG" "[INFO] Downloading checksum file..."
        curl -fsSL -o kubelet.sha256sum "$PATH_SHA256" || { logger -t "$LOG_TAG" "[ERROR] Failed to download checksum file"; exit 1; }
        
        logger -t "$LOG_TAG" "[INFO] Verifying checksum..."
        awk '{print $1"  kubelet"}' kubelet.sha256sum | sha256sum -c - || { logger -t "$LOG_TAG" "[ERROR] Checksum verification failed!"; exit 1; }
        
        logger -t "$LOG_TAG" "[INFO] Installing kubelet..."
        install -m 755 kubelet "$INSTALL_PATH"
        
        logger -t "$LOG_TAG" "[INFO] kubelet successfully updated to $COMPONENT_VERSION_CLEAN."
        rm -rf "$TMP_DIR"

      else
        logger -t "$LOG_TAG" "[INFO] kubelet is already up to date. Skipping installation."
      fi
    owner: root:root
    path: /etc/default/kubelet/download-script.sh
    permissions: "0755"
  - content: |
      COMPONENT_VERSION="{{ .kubeletVer }}"
      REPOSITORY="https://dl.k8s.io"
    owner: root:root
    path: /etc/default/kubelet/download.env
    permissions: "0644"
  - content: |
      [Unit]
      Description=Install and update kubelet
      After=network.target
      Wants=network-online.target

      [Service]
      Type=oneshot
      EnvironmentFile=-/etc/default/kubelet/download.env
      ExecStart=/bin/bash -c "/etc/default/kubelet/download-script.sh"
      RemainAfterExit=yes

      [Install]
      WantedBy=multi-user.target
    owner: root:root
    path: /usr/lib/systemd/system/kubelet-install.service
    permissions: "0644"
  - content: |
      # Note: This dropin only works with kubeadm and kubelet v1.11+
      [Service]
      Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
      Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
      # This is a file that "kubeadm init" and "kubeadm join" generates at runtime, populating the KUBELET_KUBEADM_ARGS variable dynamically
      EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
      # This is a file that the user can use for overrides of the kubelet args as a last resort. Preferably, the user should use
      # the .NodeRegistration.KubeletExtraArgs object in the configuration files instead. KUBELET_EXTRA_ARGS should be sourced from this file.
      EnvironmentFile=-/etc/default/kubelet/extra-args.env
      ExecStart=
      ExecStart=/usr/local/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS
    owner: root:root
    path: /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf
    permissions: "0644"
  - content: |
      [Unit]
      Description=kubelet: The Kubernetes Node Agent
      Documentation=https://kubernetes.io/docs/
      Wants=network-online.target containerd.service
      After=network-online.target containerd.service
      Wants=containerd.service

      [Service]
      ExecStart=/usr/bin/kubelet
      Restart=always
      StartLimitInterval=0
      RestartSec=10

      [Install]
      WantedBy=multi-user.target
    owner: root:root
    path: /usr/lib/systemd/system/kubelet.service
    permissions: "0644"
  - content: |
      {{ .mergedKubeletConfigYaml | nindent 18 }}
    owner: root:root
    path: /var/lib/kubelet/config-custom.yaml
    permissions: "0644"
  - content: |
      net.bridge.bridge-nf-call-iptables=1
      net.bridge.bridge-nf-call-ip6tables=1
    owner: root:root
    path: /etc/sysctl.d/99-br-netfilter.conf
    permissions: "0644"
  - content: |
      net.ipv4.ip_forward=1
    owner: root:root
    path: /etc/sysctl.d/99-network.conf
    permissions: "0644"
  # убрать часть с loopback  
  - content: |
      {
          "cniVersion": "0.4.0",
          "name": "lo",
          "type": "loopback"
      }
    owner: root:root
    path: /etc/cni/net.d/99-loopback.conf
    permissions: "0644"
  - content: |
      KUBELET_EXTRA_ARGS="--provider-id=beget:///{{ printf "{{ ds.meta_data.instance_id.split(':')[0] }}" }}"
    owner: root:root
    path: /etc/default/kubelet/extra-args.env
    permissions: "0644"
  - path: /etc/kubernetes/pki/ca-oidc.crt
    owner: root:root
    permissions: '0644'
    #TODO нужен параметр, который будет содержать имя clusterclaim или инфра кластера
    contentFrom:
      secret:
        name: "{{ regexReplaceAll "-(infra|client)$" .clusterName "" }}-infra-ca-oidc"
        key: ca.crt
  - content: |
      server = "https://docker.io"
      [host."https://`}}{{ .Values.composition.systemKubeApiVip }}{{ printf `/repository/registry-1-docker-io"]

        ca = "/etc/kubernetes/pki/ca-oidc.crt"
        capabilities = ["pull", "resolve"]
        priority = 1.0
        skip_verify = false

      [host."https://registry-1.docker.io"]

        capabilities = ["pull", "resolve"]
        priority = 2.0
        skip_verify = false
    owner: root:root
    path: /etc/containerd/certs.d/docker.io/hosts.toml
    permissions: "0644"
  - content: |
      server = "https://europe-docker.pkg.dev"
      [host."https://`}}{{ .Values.composition.systemKubeApiVip }}{{ printf `/repository/europe-docker-pkg-dev"]

        ca = "/etc/kubernetes/pki/ca-oidc.crt"
        capabilities = ["pull", "resolve"]
        priority = 1.0
        skip_verify = false

      [host."https://europe-docker.pkg.dev"]

        capabilities = ["pull", "resolve"]
        priority = 2.0
        skip_verify = false
    owner: root:root
    path: /etc/containerd/certs.d/europe-docker.pkg.dev/hosts.toml
    permissions: "0644"
  - content: |
      server = "https://gcr.io"
      [host."https://`}}{{ .Values.composition.systemKubeApiVip }}{{ printf `/repository/gcr-io"]

        ca = "/etc/kubernetes/pki/ca-oidc.crt"
        capabilities = ["pull", "resolve"]
        priority = 1.0
        skip_verify = false

      [host."https://gcr.io"]

        capabilities = ["pull", "resolve"]
        priority = 2.0
        skip_verify = false
    owner: root:root
    path: /etc/containerd/certs.d/gcr.io/hosts.toml
    permissions: "0644"
  - content: |
      server = "https://ghcr.io"
      [host."https://`}}{{ .Values.composition.systemKubeApiVip }}{{ printf `/repository/ghcr-io"]

        ca = "/etc/kubernetes/pki/ca-oidc.crt"
        capabilities = ["pull", "resolve"]
        priority = 1.0
        skip_verify = false

      [host."https://ghcr.io"]

        capabilities = ["pull", "resolve"]
        priority = 2.0
        skip_verify = false
    owner: root:root
    path: /etc/containerd/certs.d/ghcr.io/hosts.toml
    permissions: "0644"
  - content: |
      server = "https://mirror.gcr.io"
      [host."https://`}}{{ .Values.composition.systemKubeApiVip }}{{ printf `/repository/mirror-gcr-io"]

        ca = "/etc/kubernetes/pki/ca-oidc.crt"
        capabilities = ["pull", "resolve"]
        priority = 1.0
        skip_verify = false

      [host."https://mirror.gcr.io"]

        capabilities = ["pull", "resolve"]
        priority = 2.0
        skip_verify = false
    owner: root:root
    path: /etc/containerd/certs.d/mirror.gcr.io/hosts.toml
    permissions: "0644"
  - content: |
      server = "https://public.ecr.aws"
      [host."https://`}}{{ .Values.composition.systemKubeApiVip }}{{ printf `/repository/public-ecr-aws"]

        ca = "/etc/kubernetes/pki/ca-oidc.crt"
        capabilities = ["pull", "resolve"]
        priority = 1.0
        skip_verify = false

      [host."https://public.ecr.aws"]

        capabilities = ["pull", "resolve"]
        priority = 2.0
        skip_verify = false
    owner: root:root
    path: /etc/containerd/certs.d/public.ecr.aws/hosts.toml
    permissions: "0644"
  - content: |
      server = "https://quay.io"
      [host."https://`}}{{ .Values.composition.systemKubeApiVip }}{{ printf `/repository/quay-io"]

        ca = "/etc/kubernetes/pki/ca-oidc.crt"
        capabilities = ["pull", "resolve"]
        priority = 1.0
        skip_verify = false

      [host."https://quay.io"]

        capabilities = ["pull", "resolve"]
        priority = 2.0
        skip_verify = false
    owner: root:root
    path: /etc/containerd/certs.d/quay.io/hosts.toml
    permissions: "0644"
  - content: |
      server = "https://registry-1.docker.io"
      [host."https://`}}{{ .Values.composition.systemKubeApiVip }}{{ printf `/repository/registry-1-docker-io"]

        ca = "/etc/kubernetes/pki/ca-oidc.crt"
        capabilities = ["pull", "resolve"]
        priority = 1.0
        skip_verify = false

      [host."https://registry-1.docker.io"]

        capabilities = ["pull", "resolve"]
        priority = 2.0
        skip_verify = false
    owner: root:root
    path: /etc/containerd/certs.d/registry-1.docker.io/hosts.toml
    permissions: "0644"
  - content: |
      server = "https://registry.k8s.io"
      [host."https://`}}{{ .Values.composition.systemKubeApiVip }}{{ printf `/repository/registry-k8s-io"]

        ca = "/etc/kubernetes/pki/ca-oidc.crt"
        capabilities = ["pull", "resolve"]
        priority = 1.0
        skip_verify = false

      [host."https://registry.k8s.io"]

        capabilities = ["pull", "resolve"]
        priority = 2.0
        skip_verify = false
    owner: root:root
    path: /etc/containerd/certs.d/registry.k8s.io/hosts.toml
    permissions: "0644"
  - content: |
      server = "https://xpkg.crossplane.io"
      [host."https://`}}{{ .Values.composition.systemKubeApiVip }}{{ printf `/repository/xpkg-crossplane-io"]

        ca = "/etc/kubernetes/pki/ca-oidc.crt"
        capabilities = ["pull", "resolve"]
        priority = 1.0
        skip_verify = false

      [host."https://xpkg.crossplane.io"]

        capabilities = ["pull", "resolve"]
        priority = 2.0
        skip_verify = false
    owner: root:root
    path: /etc/containerd/certs.d/xpkg.crossplane.io/hosts.toml
    permissions: "0644"

format: cloud-config
joinConfiguration:
  discovery: null
  nodeRegistration:
    imagePullPolicy: IfNotPresent
    kubeletExtraArgs:
      - name: cloud-provider
        value: external
      - name: cluster-dns
        value: {{ default "29.64.0.10" .clusterDNS | quote }}
      - name: cluster-domain
        value: {{ default "cluster.local" .clusterDomain | quote }}
      - name: config
        value: /var/lib/kubelet/config-custom.yaml
      - name: node-labels
        value: {{ printf "node-group.beget.com/name=%%s" .machineDeploymentName | quote }}
    #   {{- if .taints }}
    # taints:
    #   {{- range .taints }}
    #   - key: {{ .key | quote }}
    #     value: {{ .value | quote }}
    #     effect: {{ .effect | quote }}
    #   {{- end }}
    #   {{- else }}
    taints: []
      # {{- end }}
preKubeadmCommands:
  - apt install -y wget tree net-tools conntrack socat jq
  - export KUBEADM_CONFIG_FILE=$(find /var/run/kubeadm/*.yaml)
  - export ADVERTISE_ADDRESS=$(ip -j addr show eth1 | jq -r '.[].addr_info[] | select(.family
    == "inet") | .local')
  - envsubst < ${KUBEADM_CONFIG_FILE} > ${KUBEADM_CONFIG_FILE}.tmp && mv ${KUBEADM_CONFIG_FILE}.tmp
    ${KUBEADM_CONFIG_FILE}
  - modprobe overlay
  - modprobe br_netfilter
  - sysctl --system
  - systemctl restart containerd-install.service
  - systemctl enable runc-install
  - systemctl start runc-install
  - systemctl enable crictl-install
  - systemctl start crictl-install
  - systemctl enable kubectl-install
  - systemctl start kubectl-install
  - systemctl enable kubeadm-install
  - systemctl start kubeadm-install
  - systemctl enable kubelet
  - systemctl enable kubelet-install
  - systemctl start kubelet-install
  - systemctl enable containerd
  - systemctl enable containerd-install
  - systemctl start containerd
  - systemctl restart systemd-resolved
users:
  - name: capv
    shell: /bin/bash
    sshAuthorizedKeys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINGPb8b0krR7l/tH7m9g59SLlvFRe05aZfx8ZR7UBeT4 @dobry_kot
      - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC973OhTJ7214Kv0oJuHo4C9epzLqNdl+LSMcPALWRMWFAXilgtLu32ERkHUNakLbS5+ZQNPH8bVaA/dGmpSEegaokvF6dXSfuVeC9OM5BAgZ7QDhgYtPn7lC4kkzQ/KWX62K5Jo7q8dme8qOE4W0NqBu09Q3AxpeCg1WoMOXGBPVksctO5icsZy88vlHJQuJx3gJEWES07Nw053d+wLbsbhsWE2UvS4sYfRlj1i2ODvBm5JgMEu6+O1RsUJkSJ9yEgsjAd1XEhwcBztuoRc6ubcOekQ5bqfZDI9L324f1DbgXrhl6ojAqYzqIEscCRIgE8Qli5FwvifHpt9zQ/0Bwi4qIqH7yatca/Nh5VYJNLeVyje0KUS8h5epDXVFz2j/js9+moOUSDxjV4Y12yv+9YA+DrsG1pwocDo4gea9APChM+oynyHX02n06fJgejVZF+g07VB5UxbtDrCl5ZTWipv7ptg5noRLUQhhC11S+RjGi0wi5vEt39qS4ZRHcKgg8= @shynie42
      - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCcraQN1wxh3D/Gi7M56BLxInIscCGos+QMQel4oweBco4gc6TqGLcQdteipnYgYGBQ3YzU0RG34qTKQ+BMq7o4+iYTF/MSF1Zj5K+nwG1xP6AaxGh5h1w2dTuv4MOEbWDiQU8l70wITDigSktonHwXgz+nDG9VjcfOgf5kfij5lok0BTtuNlaQPqm1fJ9CrSWwzIsU1GjIX0oLR0wpYLwm9lPtMSEgpfyAr8vmTwt3xPvv57WbGCjjqW1uFuiUxj7l9UF+7SkN0yOqyu+KLz79pvrhtqWK9dfx12GZpuWnZLRaLYmgHHK/rE6qlMD1NPV800XAV5y4+pV7T0d0xAogQ03ppkWG8kLjRUTWA3x5GvA6PxS4HtWKR3NCFKh/KX0+FADUbr1eYlz/dl3eRQ0UBrg8LIbLOEoagGKr8NYPHyDAfCTn3oPvxUTKB5qk0GpWOZ39h9hiUVBvYxRs5Q+kSgwiLBJ08iyUCz+DsUdf/VWto5sBxkkZiP43QRkHlsc= @Mistrikoff
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJeBpQ7CPTPutxy9g1rURRSw6HZRGtkmFLzyy9rHlBcp @godjee
      - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQD3UEO6WQP1UdA9mfCT/ZBefBJM4pLJ97E1l0c3CCr29apGNjMmRN8whyGcbU0xkL+fMjRuzrbuFwHqvSuW5sd113Hlw8A95QEnD81jWUJqhbzVS5LSQlq1A8DUjYrEW9B07gIBbWEUBWE/ZoYIMyPw5ggG3EXF/X1+JQcXcfmoitT9qVbVGHhMQItOlCj/LbntIl0NgUFgNieUJtUOY9Q9ZgnmE4ehUHRkOUd8blkGfOa+xuV1SZnK1ndEOq2dHTWpCnSRpdjcF3y9rrmwHUEYeRiMGt6Rhi4toSABQNGavLJjw2PmIldTtc4ixY7JBzYffuOOKNv5OD4nkRswVDgL ubuntu@vm-sivanov
      - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC/lJUBs6L6qsqcPXRVV3rRe/eCt+rySjI3XchRXjJ6N1n1+B1x3UgUe8tt+ngz2F47AUR30g9Brh5agy8ZtmTWux+TQ6UKiyMrh/JWg6b4PE935lfq/hBk40rJIGA3svHZkwdzThR96Ij8l73afhJqgSy28TqCGbkzZTWlZbULZhlnew1XBvwP0WI3Y78PsCsx97eQnycuzPlZAnkmzQnXlxjMPchUv+wGA2l4l39nFNwJ5bBIaxEV4b5FiStGTFjrR9fL8WoNjrRx34NLmIDQF1LxUS/13TUycPNwOSBZetQqnmgfnaPDoz16H8QFCWW6N6GkgK2weGDn5WH9hdcwY3fySwsoEoyRZmZauGfmNpvgFOWh4aS5u0VoKnmGE50gD+6Qt+Dghg91OCKEoH3cVVs1MUbOD1cqpj3Dsg6khUj93fKc8yme7CncTwYhWSwDOxYlORB0Znn7XWDYFwDtXnscqS/JoU7nglnH0AmF0ZnaAVsH8V0hDkdIslo2BPfkGsKWoO4mgBHcjGwabAfVPEUwywvVVav0mJzk7/7FlvTxrb15puQ3gZungvCWMhRV7FsOBL6P7SBFJDtGuBBIdshwztppAmjS4lppFghkXz9fRI1ZnO7ioIzQTAdKarpF788uFf57Ug0Wl10aiXGeW1K8+sDuE0XaWxKpyiMq5w== @dmkolbin
    sudo: ALL=(ALL) NOPASSWD:ALL

  ` -}}
{{- end -}}