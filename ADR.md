**ADR: Integrating Vault with Kubernetes**

**1. Context:**

ZBI Kubernetes requires a secret management solution. While Kubernetes offers native secret management capabilities, this approach does not meet the stringent security requirements demanded by Infrastructure as Code (IaC) practices. Since CBA is already using HashiCorp Vault, ZBI Kubernetes will leverage HashiCorp Vault as a secret store. Vault boasts advanced features such as dynamic secrets, encryption as a service, and fine-grained access control, rendering it an optimal choice for our security needs. Although there are many ways of integrating HashiCorp Vault with Kubernetes, in this ADR, we will explore **Vault Agent Injector** and **Vault CSI Provider**.

**2. Similarities between Vault Agent Injector and Vault CSI Provider:**

Both Agent Injection and Vault CSI solutions have the following similarities:
- Simplify retrieving different types of secrets stored in Vault and expose them to the target pod running on Kubernetes. There is no need to change the application logic or code to use these solutions, therefore, making it easier to migrate brownfield applications into Kubernetes. Developers working on greenfield applications can leverage the Vault SDKs to integrate with Vault directly.

- Support all types of Vault [secrets engines](https://developer.hashicorp.com/vault/docs/secrets), ranging from static key-value secrets to dynamically generated database credentials and TLS certs with customized TTL.

- Leverage the Kubernetes pod service account token as [Secret Zero](https://www.hashicorp.com/resources/secret-zero-mitigating-the-risk-of-secret-introduction-with-vault) to authenticate with Vault via the Kubernetes auth method. There is no need to manage yet another separate identity to identify the application pods when authenticating to Vault.

- Secret lifetime is tied to the lifetime of the pod. While this holds true for file contents inside the pod, this also holds true for Kubernetes secrets that CSI creates. Secrets are automatically created and deleted as the pod is created and deleted.

- Require the desired secrets to exist within Vault before deploying the application.

- Require the pod’s service account to bind to a Vault role with a policy enabling access to desired secrets (that is, Kubernetes RBAC isn’t used to authorize access to secrets).

- Require successfully retrieving secrets from Vault before the pods are started.

**3. Differences between Vault Agent Injector and Vault CSI Provider:**

| **Differences**        | **Vault Agent Injector**                                                                                                  | **Vault CSI Provider**                                                                                              | **Evaluation**                                                                                         | **Verdict**            |
|------------------------|----------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------|------------------------|
| Deployment             | Vault Sidecar Agent Injector solution is composed of two elements: <ul><li>The Sidecar Service Injector, deployed as a **cluster service**, intercepts Kubernetes apiserver pod events and mutates pod specs to add required sidecar containers.</li><li>The Vault Sidecar Container, deployed alongside each application pod, authenticates with Vault, retrieves secrets from Vault, and renders secrets for applications' consumption.</li></ul> | Vault CSI Provider, deployed as a **daemonset**, uses the `SecretProviderClass` and the pod’s service account to retrieve the secrets from Vault; then mounts secrets into the pod’s CSI volume. | Vault Sidecar Agent Injector requires that a sidecar container in each pod, which will cause these undesirable effects: <ul><li>**Resource Overhead**: Each application pod will require a sidecar container</li><li>**Debugging Complexity**: Identifying and troubleshooting issues related to sidecar containers adds complexity to the debugging process</li><li>**Increased Monitoring Noise**: With Vault Sidecar Agent Injector, every pod creation, deletion, or update triggers corresponding events for both the main application container and the sidecar container. This results in a higher frequency of pod lifecycle events being generated within the Kubernetes environment, leading to increased noise in monitoring systems and event logs</li></ul> Vault CSI Provider offers a much simpler deployment workflow and interaction with Vault | Vault CSI Provider |
| Authentication method  | Vault Sidecar Agent Injector supports **all** Vault auto-auth methods                                                       | The Sidecar CSI driver supports **only Vault’s Kubernetes auth** method.                                              | Since we are integrating with only ZBI Kubernetes, there is no need to use other Vault auto-auth methods.<br>Hence other Vault auto-auth methods Vault Sidecar Agent Injector offered by Vault Sidecar Agent Injector will only bring overhead and vulnerabilities. | Vault CSI Provider   |
| Secret Retrieval & Projection | The Vault Sidecar Container retrieves secrets from Vault, and mounts secrets in either: <ul><li>**Shared Memory Volume**</li><li>**Environment Variables** (achieved through Agent templating)</li></ul> | Vault CSI Provider uses hostPath to mount **Ephemeral Volumes** into the pods, and it also supports rendering Vault secrets into **Kubernetes secrets** and **environment variables**. | Vault CSI Provider is superior since it supports rendering Vault secrets into **Kubernetes secrets** and **environment variables** without the need for templating | Vault CSI Provider   |

**4. Decision:**

After thorough evaluation, we have elected to implement **Vault CSI Provider**. The simpler deployment, less resource overhead & complexity, and utilization of Kubernetes secrets align closely ZBI Kubernetes' requirements for a secret management solution.