# Declarative GitOps for a Homelab

My take on self-hosted GitOps with Kubernetes and ArgoCD

## Overview 

This repository contains the configuration for a complete GitOps Continuous Delivery pipeline, self hosted in Kubernetes. If you would like to use this project in your own homelab, see [Installation](#installation).

![](docs/architecture.svg)

## Motivation

This project stems from a desire to graduate from a Docker-compose based homelab, affording the following benefits:

* Fully declarative application state, with version control and rollbacks
* High availability (HA) at hardware and software layers, allowing individual machines to fail gracefully
* Vaulted secrets
* Production-grade tools and practices

## Architecture

### Software Components

* [k3s](https://k3s.io/): Kubernetes distribution, deployed on three server nodes
* [ArgoCD](https://argo-cd.readthedocs.io/en/stable/): Continuous Delivery tool for Kubernetes
* [Gitea](https://about.gitea.com/): Selfhosted Git server, acting as the GitOps source of truth
* [External Secrets Operator](https://external-secrets.io/latest/): Creates Kubernetes secrets from vault
* [Vaultwarden](https://github.com/dani-garcia/vaultwarden): Community Bitwarden server, used as secrets vault and as user-facing application
* [Longhorn](https://longhorn.io/): Distributed block storage for HA of volumes on local nodes and remote backups on [Backblaze B2](https://www.backblaze.com/cloud-storage)
* [cert-manager](https://cert-manager.io/): TLS certificate management leveraging [Traefik](https://traefik.io/traefik) and [LetsEncrypt](https://letsencrypt.org/) to automatically issue signed certificates to applications
* [Ansible](https://docs.ansible.com/) is used to deploy k3s via the excellent [k3s-ansible](https://github.com/k3s-io/k3s-ansible)
* [NextCloud](https://nextcloud.com/): Cloud file storage. Shown here as an example of a user-facing application that can be deployed using the above infrastructure

The Kubernetes resources above are deployed as a self-referential set of [ArgoCD applications](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/). That is, the Kubernetes manifest and Helm Values for the infrastructure is stored in the same repo that is used to deploy applications. As an example, changes to ArgoCD state can be acheived by editing files in the `argocd/` directory of this repo, pushing the update to Gitea, then deploying using ArgoCD itself.  

### Continuous Delivery

This repo is stored on the Kubernetes-hosted Gitea server. Updates to that repo trigger ArgoCD to update Applications, which are in turn deployed to the cluster. Stated another way, the state of this repo on Gitea represents the state of applications in the cluster. 

An [app-of-apps](https://argo-cd.readthedocs.io/en/latest/operator-manual/cluster-bootstrapping/) approach is taken here, where the helm chart in `apps/` is used to generate `application` manifests. Each application folder is a hybrid of upstream helm chart `values.yaml` files and raw manifests. 

As an example, the following diagram shows how to change the configuration for the Vaultwarden vault:

![](docs/cd.svg)

By editing the Helm values file in the `vaultwarden/` directory, the state of the application is changed. 

### Secrets

Vaultwarden is used as a secrets vault, and External Secrets Operator (ESO)  is used to interface between Vaultwarden and Kubernetes `secret` resources. 

ESO has several (Cluster)SecretStores available to interface with Bitwarden Password Manager, which allows for secret data to be stored and managed inside of the Vaultwarden server. [This example](https://external-secrets.io/latest/examples/bitwarden/) from ESO was followed to integrate ESO and Vaultwarden. 

Raw secret data, such as passwords, is stored in Vaultwarden. ESO `ClusterSecretStore` and `ExternalSecret` resources are used with a dedicated Bitwarden CLI API pod to connect Vaultwarden data and Kubernetes secrets. The following diagram illustrates how applications receive secret data:

![](docs/secrets.svg)

### Storage

Longhorn is used for high availability volumes, allowing individual node failures without requiring NAS or RAID hardware. An optional non-replicated storage class is included for large volumes that may not need high availability. Longhorn works with S3-compatible backup stores, and Backblaze is used here to store volume backups. Periodic jobs on Longhorn allow for full 3-2-1 volume backups. 

### Certificates

`cert-manager` automatically issues requests to Let's Encrypt for TLS certificates using ACME DNS01 challenges if an ingress references a `cluster-issuer` resource in `metadata.annotations`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
# ...
```

The approach that I've taken is to use [CloudFlare DNS01 challenges](https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/). By migrating my domain's DNS to CloudFlare, I am more easily able to sign certificates for free without opening port 80. [Many other options](https://cert-manager.io/docs/configuration/acme/), including self signed CAs or HTTP01 ACME challenges, are possible with `cert-manager`.

### Hardware

This repo is designed independent of hardware configuration, and should be compatible with any number of nodes running any k8s distribution (provided Traefik is installed). 

My physical cluster is composed of three machines each running [Proxmox VE](https://proxmox.com/en/products/proxmox-virtual-environment/overview) with one Ubuntu Server VM. Three nodes allows for [High Availability Embedded etcd](https://docs.k3s.io/datastore/ha-embedded), which in turn allows individual nodes to fail gracefully. 


### External Networking

This repo only expects that applications can be routed to based on their FQDN on port 443. However, single DNS entries are insufficient to ensure traffic is routed correctly when a node fails. If HA is a requirement, steps must be taken outside the cluster to ensure DNS is resilient to node failures. 

My approach was to leverage the HAProxy package in pfSense to load balance between my three nodes. I would have rather used Traefik here - HA proxy and its pfSense GUI are comparatively difficult to navigate. However, keeping DNS management where it already exists within pfSense was very appealing to me from a maintenance perspective. One drawback with this approach is that a DNS entry must be manually added to pfSense each time a new ingress is created. 

Here is a diagram outlining how traffic flows to pods:

![](docs/networking.svg)

My HA Proxy config consists of a single `ssl/https` type front end that uses a single backend. That backend uses a `basic` check with `source` load balancing to select between 3 servers, each with encrypt on and SSL checks off. Using a `Stick-table expire` of `5m` helps cutting back to healthy nodes quickly. Most other settings are left default or disabled. 

### Repo Structure

Most directories in this repository house application configurations (Helm `values.yaml` and raw Kubernetes manifests). Utilities for installation, data initialization, and disaster recovery are stored in `tools/`. 

```sh
├── apps                        # App-of-apps application configs
├── argocd                      # ArgoCD application configs
├── cert-manager                # cert-manager application configs
├── docs                        # Readme assets
├── external-secrets            # ESO application configs
├── gitea                       # Gitea application configs
├── longhorn                    # Longhorn application configs
├── nextcloud                   # NextCloud application configs
├── tools
│   ├── bootstrap               # Installation and disaster recovery Helm chart 
│   ├── nextcloudVolumeInit     # NextCloud data migration
│   └── vaultwardenVolumeInit   # Vaultwarden data migration
└── vaultwarden                 # Vaultwarden application configs
```

## Installation

The [tools](tools/README.md) directory contains several tools for deploying this repo into your own cluster. Follow the instructions in the [bootstrap tool README](tools/bootstrap/README.md) to set up this repository. If migrating data from existing Vaultwarden or Nextcloud servers, see the [vaultwardenVolumeInit](tools/vaultwardenVolumeInit/README.md) and [nextcloudVolumeInit](tools/nextcloudVolumeInit/README.md) READMEs. Before final deployment, follow the steps in [Configuration](#configuration). 

## Configuration

Some applications will require configuration for secrets and ingresses:

* ArgoCD
    * Edit `global.domain` and `server.ingress.extraTls[0].hosts` in [values.yaml](argocd/values.yaml)
* Cert-manager
    * Edit `spec.acme.email` for both issuers in [clusterissuers.yaml](cert-manager/clusterissuers.yaml)
    * Add the CloudFlare API token secret to Vaultwarden, then update the UUID to match in [externalsecret.yaml](cert-manager/externalsecret.yaml). See the Vaultwarden steps below for details. 
* Gitea
    * Edit `ingress.hosts[0].host` and `ingress.tls[0].hosts` in [values.yaml](gitea/values.yaml)
* Longhorn
    * Edit `ingress.host` and `defaultBackupStore.backupTarget` in [values.yaml](longhorn/values.yaml)
    * Add the Backblaze secret to Vaultwarden, and update the UUID to match in [externalsecret.yaml](longhorn/externalsecret.yaml). See the Vaultwarden steps below for details.
* Nextcloud
    * Set up Vaultwarden first
    * If you have an existing Nextcloud server, use [tools/nextcloudVolumeInit](tools/nextcloudVolumeInit/README.md) to migrate the data 
    * Add the Nextcloud admin and database secrets to Vaultwarden, then update the UUID to match in [externalsecrets.yaml](nextcloud/externalsecrets.yaml)
* Vaultwarden
    * If you have an existing Vaultwarden server, use [tools/vaultwardenVolumeInit](tools/nextcloudVolumeInit/README.md) to migrate the data
    * If you are not using the `vaultwardenVolumeInit` tool:
        * Create secret resources for the admin password. See the [tool README](tools/vaultwardenVolumeInit/README.md#usage) for details
        * Add a service account to Vaultwarden. See the [vaultwardenVolumeInit](tools/nextcloudVolumeInit/README.md) readme for details
    * Some secrets need to be created in Vaultwarden and available to the service account. Once the secrets have been added, they can be referenced in `ExternalSecret` manifests by referencing the URL itemId parameter:
        ```
        https://myvault.com/#/vault?type=login&itemId=aaaabbbb-cccc-dddd-eeee-000011112222
        ```
        * [See here](https://external-secrets.io/latest/examples/bitwarden/)
        * I have found it useful to store these secrets in a dedicated org, accessible to both the service account and your personal account. This allows you to administer secrets without changing to the service account.

## Further edits

### Editing upstream Helm charts

Edits to applications can be made by updating the upstream Helm charts through the `values.yaml` file. I like to inspect the default values, and only include overwrites in the `values.yaml` file. 

For convenience, you can generate the default `values.yaml` file for the exact chart version and store it on disk using the `helm` CLI utility. Longhorn is shown here as an example, using information from [apps/values.yaml](apps/values.yaml)

```sh
helm repo add longhorn https://charts.longhorn.io
helm repo update 
helm show values longhorn/longhorn --version 1.9.1 > longhorn/defaultValues.yaml
```

## Appendix A: Connecting disks directly to longhorn

This repo does not cover host OS-level setup, including disk management. The steps here show how to dedicate an entire physical disk to Longhorn by configuring it on Proxmox and within the VM OS. 

* Start with a blank unformatted disk
* Follow [this guide](https://dannyda.com/2020/08/26/how-to-passthrough-hdd-ssd-physical-disks-to-vm-on-proxmox-vepve/), and reference [proxmox docs](https://pve.proxmox.com/wiki/Passthrough_Physical_Disk_to_Virtual_Machine_(VM)). To summarize:
    ```sh
    # From proxmox shell
    apt install lshw
    lshw -class disk -class storage
    ls -l /dev/disk/by-id/ # Note matching disk ID
    # `100` is VM ID, ata-xxxxxxxxx-xxxxx_xxx is disk ID
    qm set 100 -scsi5 /dev/disk/by-id/ata-xxxxxxxxx-xxxxx_xxx
    ```
* Find disk name with `lsblk -o NAME,SIZE,MODEL,SERIAL` from VM
* Find disk ID with `ls /dev/disk/by-id -lah` (Match with drive name, EG `sdb`)
    ```sh
    sudo mkfs.ext4 -F /dev/sdb
    sudo mkdir -p /mnt/longhorn
    sudo mount -o discard /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi5 /mnt/longhorn
    echo '/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi5 /mnt/longhorn ext4 defaults,discard 0 0' | sudo tee -a /etc/fstab
    sudo mount -a
    ```
* In Longhorn GUI, `Node` tab, Operation menu on right, `Edit Node and Disks`, add disk at bottom
    * Use `File System` disk type
    * Use the mount point `/mnt/longhorn` NOT `/dev/sdb`
    * Enable scheduling

## Appendix B: Expanding volumes 

Longhorn makes use of the k3s server node's logical volume. The partition and LV may need to be expanded on the OS to fill the disk:

1. Identify the device and partition names. Here is an example of an under provisioned disk - `ubuntu--vg-ubuntu--lv` is only 100GB on a 980GB disk:
    ```sh
    $ lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
    NAME                       SIZE FSTYPE      MOUNTPOINT
    sda                        980G             
    ├─sda1                       1M             
    ├─sda2                       2G ext4        /boot
    └─sda3                     978G LVM2_member 
    └─ubuntu--vg-ubuntu--lv  100G ext4        /
    ```
1. Expand the logical volume:
    ```dh
    sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
    ```
1. Resize the file system
    ```sh
    sudo resize2fs /dev/ubuntu-vg/ubuntu-lv
    ```

The Longhorn dashboard should now show the full disk size on the Nodes tab.