# K8s with Vault Injector

vault policy write app1-dev-injector-policy - <<EOF
path "app1-dev/secrets/db-pass" {
  capabilities = ["read"]
}
EOF

vault policy read app1-dev-injector-policy

vault write auth/cluster1/role/app1-dev-injector-role \
    bound_service_account_names=app1-dev-injector-sa \
    bound_service_account_namespaces=app1-dev \
    policies=app1-dev-injector-policy \
    ttl=2h

k apply -f app.yaml

k exec \
      $(kubectl get pod -l app=orgchart -o jsonpath="{.items[0].metadata.name}") \
      --container orgchart -- ls /vault/secrets

k patch deployment orgchart --patch "$(cat patch-inject-secrets.yaml)"