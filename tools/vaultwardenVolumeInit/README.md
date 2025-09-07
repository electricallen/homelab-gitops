# Vaultwarden Volume Initializer Tool

Tool for initializing a Longhorn volume with data from an existing Vaultwarden server. See https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault.

## Required Items
* A service account (See below)
* Backup of the Vaultwarden server's `/data` directory 

### Creating a service account

This repo uses a dedicated account in Vaultwarden to store Kubernetes secrets, extracted by External-Secrets Operator using a Bitwarden CLI pod. This account should be created prior to migration. Steps are based on [this Vaultwarden github issue](https://github.com/dani-garcia/vaultwarden/discussions/4531).

In the existing environment:

1. [Enable the admin page](https://github.com/dani-garcia/vaultwarden/wiki/Enabling-admin-page)
1. Enable signups (General Settings > Allow new signups)
1. Navigate to `https://your.vault.tld/#signup` and create the new account. If SMTP is disabled, the account will be automatically verified and a real email address does not need to be used.
1. Disable signups and backup the `/data` directory of the Vaultwarden server

## Usage

1. `cd` to the directory with this README
1. Create a `secrets.yaml` file, then edit it to add the admin token and service account credentials:
    ```yaml
    apiVersion: v1
    kind: Namespace
    metadata:
    labels:
        kubernetes.io/metadata.name: vaultwarden
        name: vaultwarden
    name: vaultwarden
    ---
    # Vaultwarden Admin Token
    apiVersion: v1
    kind: Secret
    metadata:
        name: vaultwarden-admin-token
        namespace: vaultwarden
    type: Opaque
    stringData:
    # Argon string for MySecretPassword shown here, generated with
    #       echo -n "MySecretPassword" | argon2 "$(openssl rand -base64 32)" -e -id -k 65540 -t 3 -p 4
    #       https://github.com/dani-garcia/vaultwarden/wiki/Enabling-admin-page#using-argon2
        admin-token: '$argon2id$v=19$m=65540,t=3,p=4$bXBGMENBZUVzT3VUSFErTzQzK25Jck1BN2Z0amFuWjdSdVlIQVZqYzAzYz0$T9m73OdD2mz9+aJKLuOAdbvoARdaKxtOZ+jZcSL9/N0'
    ---
    # Bitwarden CLI service account
    apiVersion: v1
    kind: Secret
    metadata:
        name: bitwarden-cli
        namespace: vaultwarden
    type: Opaque
    stringData:
        BW_HOST: http://vaultwarden.vaultwarden.svc
        BW_USERNAME: serviceAccountName@k8s.yourdomain.tld
        BW_PASSWORD: some-super-strong-password-here
    ```
1. Create the new secrets
    ```sh
    kubectl apply -f secrets.yaml
    ```
1. Place backup data at `./vaultwardenData`. If this is on another server somewhere, you could retrieve it with EG `scp -r user@your.server.example.com:/path/to/data ./vaultwardenData`
1. Execute the tool
    ```sh
    sh init.sh
    ```
1. Vaultwarden can now be deployed, EG `argocd app sync vaultwarden`