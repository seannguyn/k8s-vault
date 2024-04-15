# K8s with Vault CSI

#create ns
k apply -f /k8s-vault/vault-csi/ns.yaml

#set context
k config set-context --current --namespace=app1-dev

#k8s sa,role,secret
k apply -f /k8s-vault/vault-csi/sa-vault.yaml

#token
export K8S_TOKEN=$(k get secret app1-dev-sa-secret -o jsonpath="{.data.token}" | base64 -d)
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
vault auth enable --path=kubernetes/cluster1 kubernetes

vault write auth/kubernetes/cluster1/config \
    token_reviewer_jwt="$K8S_TOKEN" \
    kubernetes_host="$K8S_HOST" \
    kubernetes_ca_cert="$K8S_CA_CRT" \
    disable_local_ca_jwt=true

vault read auth/kubernetes/cluster1/config

#create valut secret, secret policy
vault secrets enable -path=/app1-dev/secrets kv
vault kv put app1-dev/secrets/db-pass pwd="admin@123"
vault kv get app1-dev/secrets/db-pass

vault policy write app1-dev-policy - <<EOF
path "app1-dev/secrets/db-pass" {
  capabilities = ["read"]
}
EOF
vault policy read app1-dev-policy

# TEST THIS. WHAT HAPPEN IF EXPRE?
vault write auth/kubernetes/cluster1/role/app1-dev-role \
    bound_service_account_names=* \
    bound_service_account_namespaces=* \
    policies=app1-dev-policy \
    ttl=2h

vault read auth/kubernetes/cluster1/role/app1-dev-role

#create vault SecretProviderClass
k apply -f /k8s-vault/vault-csi/spc-crd-vault.yaml
k get secretproviderclass -A

#pod which mounts valut secret
k apply -f /k8s-vault/vault-csi/webapp.yaml
k get pods --watch
k exec -it webapp -- cat /mnt/secrets-store/db-password

#Change secrets to see if it is reflected. 
#It should take 30s to reflect, because of "--set rotationPollInterval=30s" in csi driver
vault kv put app1-dev/secrets/db-pass pwd="admin@789"
vault kv get app1-dev/secrets/db-pass

#Check again, it should be admin@789
k exec -it webapp -- cat /mnt/secrets-store/db-password

# curl Vault for verification
curl -H "X-Vault-Token: $TOKEN" \
    -X LIST http://10.16.61.86:8200/v1/auth/kubernetes/cluster1/role | jq

curl -X POST \
     --data "{\"role\": \"app1-dev-role\",\"jwt\": \"$K8S_TOKEN\" }" \
     http://10.16.61.86:8200/v1/auth/kubernetes/cluster1/login

curl -H "X-Vault-Request: true" \
    -H "X-Vault-Token: $TOKEN" \
    http://10.16.61.86:8200/v1/app1-dev/secrets/db-pass

