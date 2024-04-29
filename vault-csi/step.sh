################################################ PHASE 1: INSTALL CSI DRIVER, VAULT CSI PROVIDER ################################################
###### Install Secret store CSI driver
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm upgrade -i csi secrets-store-csi-driver/secrets-store-csi-driver \
    --kubeconfig ~/.kube/config \
    --set syncSecret.enabled=true \
    --set enableSecretRotation=true \
    --set rotationPollInterval=30s \
    --set syncSecret.enabled=true

###### Install Valut CSI Provider
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault \
    --kubeconfig ~/.kube/config \
    --set "server.enabled=false" \
    --set "global.externalVaultAddr=http://10.16.61.86:8200" \
    --set "injector.enabled=false" \
    --set "csi.enabled=true" \
    --set "csi.extraArgs={-vault-mount=kubernetes/nw-dev}"





################################################ PHASE 2: VAULT CONFIGURATION ################################################################################################
### Get k8s ca cert
export K8S_CA_CRT=$(k get cm kube-root-ca.crt -o jsonpath='{.data.ca\.crt}')
echo $K8S_CA_CRT

### Get k8s host
export K8S_HOST=$(k config view --raw -o 'jsonpath={.clusters[].cluster.server}')
echo $K8S_HOST

### Create vault k8s auth
vault login $TOKEN
vault auth enable --path=kubernetes/nw-dev kubernetes

vault write auth/kubernetes/nw-dev/config \
    kubernetes_host="$K8S_HOST" \
    kubernetes_ca_cert="$K8S_CA_CRT"

vault read auth/kubernetes/nw-dev/config

MOUNT_ACCESSOR=$(vault auth list --format=json | jq -r '.["kubernetes/nw-dev/"].accessor')
echo $MOUNT_ACCESSOR


### Create role
vault write auth/kubernetes/nw-dev/role/default \
    bound_service_account_names=* \
    bound_service_account_namespaces=* \
    alias_name_source=serviceaccount_name
vault read auth/kubernetes/nw-dev/role/default


### Create policy for app1-dev
vault policy write app1-dev-policy - <<EOF
path "app1-dev/secrets/db-pass" {
  capabilities = ["read"]
}
EOF
vault policy read app1-dev-policy

### Create entity for app1-dev
vault write identity/entity name=app1-dev/app1-dev-sa
ENTITY_ID=$(vault read identity/entity/name/app1-dev/app1-dev-sa --format=json | jq ".data.id" -r)
echo $ENTITY_ID

### Create entity alias for app1-dev
vault write identity/entity-alias \
    name=app1-dev/app1-dev-sa \
    canonical_id=$ENTITY_ID \
    mount_accessor=$MOUNT_ACCESSOR

### Create group for app1-dev
vault write identity/group \
    name=app1-dev \
    type=internal \
    member_entity_ids=$ENTITY_ID \
    policies=app1-dev-policy




### Create policy for app1-stg
vault policy write app1-stg-policy - <<EOF
path "app1-stg/secrets/db-pass" {
  capabilities = ["read"]
}
EOF
vault policy read app1-stg-policy

### Create entity for app1-stg
vault write identity/entity name=app1-stg/app1-stg-sa
ENTITY_ID=$(vault read identity/entity/name/app1-stg/app1-stg-sa --format=json | jq ".data.id" -r)
echo $ENTITY_ID

### Create entity-alias for app1-stg
vault write identity/entity-alias \
    name=app1-stg/app1-stg-sa \
    canonical_id=$ENTITY_ID \
    mount_accessor=$MOUNT_ACCESSOR

### Create group for app1-stg
vault write identity/group \
    name=app1-stg \
    type=internal \
    member_entity_ids=$ENTITY_ID \
    policies=app1-stg-policy





################################################ PHASE 3: SECRETS USAGE ################################################################################################
# create ns: app1-dev, app1-stg
k apply -f /k8s-vault/vault-csi/ns.yaml

# set context
k config set-context --current --namespace=app1-dev

# k8s sa, clusterrolebinding
k apply -f /k8s-vault/vault-csi/sa-vault.yaml

# create vault SecretProviderClass
k apply -f /k8s-vault/vault-csi/spc-crd-vault.yaml
k get secretproviderclass -A

# create pod that consume secrets from Vault
k apply -f /k8s-vault/vault-csi/webapp.yaml
k get pods -A --watch
k exec -it webapp -n app1-dev -- cat /mnt/secrets-store/db-password
k exec -it webapp -n app1-stg -- cat /mnt/secrets-store/db-password

# Change secrets to see if it is reflected.
# It should take 30s to reflect, because of "--set rotationPollInterval=30s" in csi driver
vault kv put app1-dev/secrets/db-pass pwd="app1-dev-NEW"
vault kv put app1-stg/secrets/db-pass pwd="app1-stg-NEW"

# Check again, it should be app1-dev-NEW and app1-stg-NEW
k exec -it webapp -n app1-dev -- cat /mnt/secrets-store/db-password
k exec -it webapp -n app1-stg -- cat /mnt/secrets-store/db-password





################################################ MISCELLANEOUS ################################################
# curl Vault for verification
# TOKEN is root token, which is already set as environment variable here
# https://github.com/seannguyn/k8s-vault/blob/main/aws/infrastructure.yaml#L295
VAULT_ADDR='http://10.16.61.86:8200'
curl -H "X-Vault-Token: $TOKEN" \
    -X LIST $VAULT_ADDR/v1/auth/kubernetes/nw-dev/role | jq

curl -H "X-Vault-Request: true" \
    -H "X-Vault-Token: $TOKEN" \
    $VAULT_ADDR/v1/app1-dev/secrets/db-pass

# Verification from inside pod
VAULT_ADDR='http://10.16.61.86:8200'
SA_TOKEN=$(k exec -it webapp -n app1-dev -- cat /var/run/secrets/kubernetes.io/serviceaccount/token)
ROLE=default
VAULT_TOKEN=$(curl -s -X POST \
     --data "{\"role\": \"$ROLE\",\"jwt\": \"$SA_TOKEN\" }" \
     $VAULT_ADDR/v1/auth/kubernetes/nw-dev/login \
    | jq -r ".auth.client_token")

# This token can be validated using vault command.
# {
#   ...
#     "display_name": "kubernetes-nw-dev-app1-dev-app1-dev-sa",
#     "entity_id": "20850f44-d33b-5cb9-b83f-2441adf62403",
#     ...
#     "identity_policies": [
#       "app1-dev-policy"
#     ],
#     ...
#     "meta": {
#       "role": "default",
#       "service_account_name": "app1-dev-sa",
#       "service_account_namespace": "app1-dev",
#       "service_account_secret_name": "",
#       "service_account_uid": "f1d68258-02e2-4ca4-bc2b-a69065d47254"
#     },
#     ...
#     "path": "auth/kubernetes/nw-dev/login",
#     ...
# }
vault token lookup --format=json $VAULT_TOKEN | jq

# Here is what happens inside Vault: 
#     When the application logs in using its service account token and the Kubernetes auth role, 
#     Vault will check if the service account is allowed in the role definition, 
#     then look up the entity alias associated with the Kubernetes auth method using the name “default/application-foo-sa”. 
#     Once the entity alias is found, Vault will grant the policies associated with it and its entity to the token.
