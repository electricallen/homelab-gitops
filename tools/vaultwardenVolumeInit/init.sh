kubectl apply -f vaultwarden.yaml
kubectl -n vaultwarden wait --for=condition=ready pod -l name=vaultwarden-seeder --timeout=600s
PODNAME=$(kubectl -n vaultwarden get pods -l name=vaultwarden-seeder -o jsonpath='{.items[0].metadata.name}')
kubectl cp ./vaultwardenData/. vaultwarden/$PODNAME:/data/
kubectl wait -n vaultwarden --for=condition=complete job vaultwarden-seeder --timeout=600s
kubectl logs -n vaultwarden -l name=vaultwarden-seeder
kubectl -n vaultwarden delete pod $PODNAME