#!/bin/bash
BACKUP_FILE_PATH=./nextcloud-sqlbkp.bak
# DB volume
echo "Applying manifest..."
kubectl apply -f nextcloud.yaml
echo "Manifest applied. Waiting for NextCloud DB seeder pod to be ready..."
kubectl -n nextcloud wait --for=condition=ready pod nextcloud-db-seeder -n nextcloud --timeout=600s
echo "Seeder pod started. Copying database backup file..."
kubectl -n nextcloud cp $BACKUP_FILE_PATH nextcloud/nextcloud-db-seeder:/tmp/nextcloud-sqlbkp.bak
echo "File copied. Restoring database..."
kubectl -n nextcloud exec -t nextcloud-db-seeder -- sh -c '
mariadb -h localhost -u root -p$MARIADB_ROOT_PASSWORD -e "DROP DATABASE nextcloud;"
mariadb -h localhost -u root -p$MARIADB_ROOT_PASSWORD -e "CREATE DATABASE nextcloud;"
mariadb -h localhost -u root -p$MARIADB_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON nextcloud.* TO '\''nextcloud'\''@'\''%'\'';"
mariadb -h localhost -u root -p$MARIADB_ROOT_PASSWORD -e "FLUSH PRIVILEGES;"
mariadb -h localhost -u root -p$MARIADB_ROOT_PASSWORD nextcloud < /tmp/nextcloud-sqlbkp.bak
if [ -z "$(mariadb -h localhost -u root -p$MARIADB_ROOT_PASSWORD -e "USE nextcloud; SHOW TABLES;")" ]; then
    echo No tables found!
    exit 1
else
    echo "Database restored successfully"
fi
'
if [ $? -ne 0 ]; then
    echo "Database restore failed. Exiting script."
    exit 1
fi

kubectl -n nextcloud delete pod nextcloud-db-seeder
# Data volume
PODNAME=$(kubectl -n nextcloud get pods -l batch.kubernetes.io/job-name=nextcloud-data-seeder -o jsonpath='{.items[0].metadata.name}')
echo "Copying config.php to $PODNAME"
kubectl cp config.php nextcloud/$PODNAME:/var/www/html/config/config.php
echo "Config copied, waiting for job to complete"
kubectl -n nextcloud logs -f $PODNAME
kubectl -n nextcloud delete job nextcloud-data-seeder
echo "Data restored successfully"