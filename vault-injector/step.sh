#k8s sa,role,secret
k apply -f sa-vault.yaml

#secret name
export K8S_SECRET=$(kubectl get secrets --output=json \
    | jq -r '.items[].metadata | select(.name|startswith("vault-auth-")).name')
echo $K8S_SECRET

#token
export K8S_TOKEN=$(k get secret vault-auth-secret -o jsonpath="{.data.token}" | base64 -d)
echo $K8S_TOKEN

#ca cert
export K8S_CA_CRT=$(k get cm kube-root-ca.crt -o jsonpath='{.data.ca\.crt}')
echo $K8S_CA_CRT

#host
export K8S_HOST=$(k config view --raw -o 'jsonpath={.clusters[].cluster.server}')
echo $K8S_HOST 

# ---------------------
#create vault k8s auth
vault login $TOKEN
vault auth enable kubernetes

vault write auth/kubernetes/config \
    token_reviewer_jwt="$K8S_TOKEN" \
    kubernetes_host="$K8S_HOST" \
    kubernetes_ca_cert="$K8S_CA_CRT" \
    disable_local_ca_jwt=true

vault read auth/kubernetes/config

#create valut secret, secret policy
vault secrets enable -path=/secret kv
vault kv put secret/db-pass pwd="admin@123"
vault kv get secret/db-pass

vault policy write internal-app - <<EOF
path "secret/db-pass" {
  capabilities = ["read"]
}
EOF
vault policy read internal-app

vault write auth/kubernetes/role/database \
    bound_service_account_names=vault-auth-sa \
    bound_service_account_namespaces=default \
    policies=internal-app \
    ttl=120m

vault read auth/kubernetes/role/database

#create vault SecretProviderClass
k apply -f spc-crd-vault.yaml

#pod which mounts valut secret
k apply -f webapp.yaml
k get pods --watch
k exec -it webapp -- cat /mnt/secrets-store/db-password

#Change secrets to see if it is reflected. 
#It should take 30s to reflect, because of "--set rotationPollInterval=30s" in csi driver
vault kv put secret/db-pass pwd="admin@789"
vault kv get secret/db-pass

#Check again, it should be admin@789
k exec -it webapp -- cat /mnt/secrets-store/db-password

#export VAULT_TOKEN=$(vault print token)

# test k8s calls
k run debug-tool --image=wbitt/network-multitool

curl -H "X-Vault-Token: hvs.*********" \
    -X LIST http://10.16.61.86:8200/v1/auth/kubernetes/role | jq

curl -X POST \
    --data '{"role": "database","jwt": $K8S_TOKEN }' \
    http://10.16.61.86:8200/v1/auth/kubernetes/login

curl -H "X-Vault-Request: true" \
    -H "X-Vault-Token: hvs.*********" \
    http://10.16.61.86:8200/v1/secret/db-pass

