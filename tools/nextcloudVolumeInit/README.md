# NextCloud Volume Initializer Tool

Tool for initializing a Longhorn volume with data from an existing NextCloud server. It is presumed data is available on the host file system, either from a direct install or Docker bind mount. 

### Relevent documentation

* https://docs.nextcloud.com/server/latest/admin_manual/maintenance/backup.html
* https://docs.nextcloud.com/server/latest/admin_manual/maintenance/restore.html 
* https://docs.nextcloud.com/server/latest/admin_manual/maintenance/migrating.html

## Required Items

Data is copied with a `rysnc <user>@<host>:<path> nextcloud/PODNAME:/var/www/html` command, using credentials loaded from a Vaultwarden secret.

* Vaultwarden and External Secrets deployed
* A secret stored in Vaultwarden, accessible to the service account. This secret must be a `login` type with the following values:
    * username: The username of the source host account
    * password: The password of the source host account
    * host (custom field): The hostname of source machine
    * path (custom field): The file path to `/var/www/html` on the source host
* The contents of the `/var/www/html` directory available over ssh (this contains all user files and may be enormous)
* A backup of the nextcloud database. This can be taken with:
    ```sh
    DBUSER=nextcloud
    DBPASSWORD=someStrongPassword!
    docker exec --user www-data nextcloud php occ maintenance:mode --on
    docker exec nextcloud-db mariadb-dump --single-transaction -h localhost -u $nextcloud -p$DBPASSWORD nextcloud > ~/nextcloud/db/nextcloud-sqlbkp.bak
    docker exec --user www-data nextcloud php occ maintenance:mode --off
    ```
**NOTE**: MariaDB > v11 no longer ships with `mysqldump`. Use `mariadb-dump` to take backups, and `mariadb` to restore them on newer versions. For older versions of MariaDB, use `mysqldump` and `mysql` commands. 


## Source host setup

1. Set up passwordless `sudo` on the remote host
    ```sh
    sudo visudo
    # Add the following line to the file:
    # YOUR-USERNAME-HERE ALL=NOPASSWD:/bin/rsync
    ```
1. Enable maintenance mode on the NextCloud server
    ```sh
    docker exec -it --user=www-data nextcloud php occ maintenance:mode --on
    ```

Both of these steps can be undone once the data has been copied to the Longhorn Volume

## Usage

1. `cd` to the directory with this README
1. Edit the PVC size in `nextcloud.yaml` to accommodate the incoming data
1. Add secrets for NextCloud admin and database credentials to Vaultwarden
1. Edit `nextcloud.yaml`'s ExternalSecret to use the ID of your secret. This can be found in the URL itemId parameter: https://myvault.com/#/vault?type=login&itemId=........-....-....-....-............ [See here](https://external-secrets.io/latest/examples/bitwarden/)
1. Place the DB backup at `./nextcloud-sqlbkp.bak`, EG:
    ```sh
    scp user@host.domain.tld:/home/user/nextcloud/db/nextcloud-sqlbkp.bak ./
    ```
1. Create a new `config.php` file in this directory. This should be very similar to the existing config file. Consider only editing the trusted domains, and if a different hostname is used. In particular, these fields should remain the same:
    * `installed`
    * `instanceid`
    * `passwordsalt`
    * `secret`
    * `data-fingerprint`
    * `config.php` was a source of many issues in my testing. Be very careful and if there are issues with the migration review `config.php` first. See [Further Troubleshooting](#further-troubleshooting)
1. Run `sh nextcloud.sh`. This script does the following:
    * Applies the manifest `nextcloud.yaml`
    * Copies `nextcloud-sqlbkp.bak` into the DB seeder pod
    * Runs database restore commands
    * Copies `config.php` into the data volume
    * Cleans up unused resources
1. For the database restore, you should see this line:
    ```sh
    Database restored successfully
    ```
1. During the data restore, you'll see each filename printed. If the data restore shows an rsync error, check for any open ssh sessions on that host and run the script again.
1. Sync the NextCloud ArgoCD application using the GUI or from the CLI:
    ```sh
    argocd login <host>.<domain>.<tld>
    argocd app sync apps
    argocd app sync nextcloud
    ```
1. The NextCloud pod should now show HTTP 200 responses in the logs:
    ```sh
    > kubectl -n nextcloud logs -l app.kubernetes.io/name=nextcloud
    Defaulted container "nextcloud" out of: nextcloud, nextcloud-cron, mariadb-isalive (init)
    "GET /status.php HTTP/1.1" 200 1086 "-" "kube-probe/1.33"
    "GET /status.php HTTP/1.1" 200 1086 "-" "kube-probe/1.33"
    ```
1. NextCloud can now be safely taken out of maintenance mode:
    ```sh
    PODNAME=$(kubectl -n nextcloud get pods -l app.kubernetes.io/name=nextcloud -o jsonpath='{.items[0].metadata.name}')
    kubectl -n nextcloud wait --for=condition=ready pod $PODNAME -n nextcloud
    kubectl exec -it $PODNAME -- runuser -u www-data -- php occ maintenance:mode --off
    ```
1. The data is now fully migrated and the application deployed. You may want to disable passwordless sudo on the source server and shut down the running nextcloud server.

## Further troubleshooting

If there are any issues with the migration process, it is likely related to the `config.php` file. NextCloud file systems are very sensitive to permissions, and the errors shown can be confusing. Here are some issues I've ran into:

1. `config.php`
        * * Must have the line `'installed'
    * Must have at least `localhost` and the ingress URL added to `trusted_domains`. Somewhat confusingly, the liveness probe uses the ingress URL rather than a Kubernetes address. This means the pod will fail to start if the ingress name isn't available over DNS and included in `trusted_domains`
    * `instanceid`, `passwordsalt`, `secret`, and `data-fingerprint` should all match the source machine's `config.php` file exactly
    * Database settings must also match. If the `mariadb-isalive` init container is completing but the pod is attempting an install, it may be due to a mismatched password. You can test the `nextcloud` account password using:
        ```sh
        kubectl -n nextcloud exec nextcloud-mariadb-0 -it -- mariadb -u nextcloud -p
        ```
1. Mismatched versions
    * The source container and this deployment should have exactly matched versions. Declare a minor revision for both containers. Keep in mind NextCloud can only upgrade one major revision at a time. 