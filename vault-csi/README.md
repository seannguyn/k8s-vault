# K8s with Vault CSI

## To Test
- multi cluster config
- create everything in app1-dev namespace
- change path to app1/secrets
- change role
- change policy

- set ttl to 5m, then after 5mins,
    - change the password
    -  see what happened




https://computingforgeeks.com/how-to-integrate-multiple-kubernetes-clusters-to-vault-server/
https://discuss.hashicorp.com/t/vault-csi-provisioner-w-auth-path/25216
https://github.com/hashicorp/vault-csi-provider/blob/main/test/bats/configs/vault-all-secretproviderclass.yaml
https://developer.hashicorp.com/vault/tutorials/kubernetes/agent-kubernetes








============================================================
User
I have enabled:

vault auth enable --path=nw-dev kubernetes
vault auth enable kubernetes

pods in my nw-dev is trying to authenticate via: http://10.16.61.86:8200/v1/auth/kubernetes/login

Shouldn't it try to do it via http://10.16.61.86:8200/v1/auth/nw-dev/login

============================================================
Yes, you're correct. If you've enabled the Kubernetes authentication method at a custom path `nw-dev`, the pods in your Kubernetes cluster should be trying to authenticate using the path `http://10.16.61.86:8200/v1/auth/nw-dev/login` instead of the default path `http://10.16.61.86:8200/v1/auth/kubernetes/login`.

Here's what you can do to resolve this:

1. **Update Kubernetes Service Account Configurations**: You'll need to update the service account configurations in your Kubernetes pods to use the correct Vault path (`nw-dev` in your case) for authentication.

    Instead of using the default `vault` annotation:
    ```yaml
    annotations:
      vault.hashicorp.com/agent-inject: "true"
    ```
    Use the custom path `nw-dev`:
    ```yaml
    annotations:
      vault.hashicorp.com/agent-inject: "true"
      vault.hashicorp.com/auth-path: "nw-dev"
    ```

2. **Restart Pods**: After updating the service account configurations, you'll need to restart the pods for the changes to take effect. Kubernetes will then use the custom `nw-dev` path to authenticate with Vault.

3. **Verify Authentication**: Once the pods are restarted, you can verify if they're successfully authenticating with Vault by checking the Vault server logs and the Kubernetes pod logs. Look for any authentication errors or successful authentication messages in both sets of logs.

4. **Testing**: You can also manually test the authentication by running the following command inside one of the pods:
    ```bash
    vault write auth/nw-dev/login role=<ROLE_NAME> jwt=<SERVICE_ACCOUNT_JWT>
    ```
    Replace `<ROLE_NAME>` with the name of the Vault role bound to the Kubernetes service account and `<SERVICE_ACCOUNT_JWT>` with the JWT token of the Kubernetes service account.

By updating the service account configurations and restarting the pods, Kubernetes should now use the custom `nw-dev` path to authenticate with Vault, resolving the `404` error you encountered earlier.