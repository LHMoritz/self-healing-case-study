# Secret Expiration Simulation — Implementation Plan
## AKS + TeaStore + Azure Key Vault (DB_HOST via Secret)

This document describes the step-by-step implementation of the secret expiration experiment. The approach stores the TeaStore database hostname (`DB_HOST`) in Azure Key Vault with an expiration date, syncs it into a Kubernetes Secret, and injects it into the `teastore-persistence` deployment. This enables evaluation of whether Instana detects the secret approaching expiration and the resulting service degradation when the secret is rotated to an invalid value.

**No application code changes are required.** Only the deployment configuration is modified to source `DB_HOST` from a Kubernetes Secret instead of a hardcoded value.

---

## Prerequisites

- AKS cluster provisioned and accessible via `kubectl`
- Azure CLI (`az`) installed and authenticated (version ≥ 2.47.0)
- Existing Azure Resource Group (referenced as `<RESOURCE_GROUP>`)
- Instana agent deployed and collecting data from the AKS cluster
- TeaStore application deployed and operational in namespace `default`

---

## Architecture Overview

```
                    Azure Key Vault
                    ┌──────────────────────┐
                    │ Secret:              │
                    │  teastore-db-host    │
                    │  value: "teastore-db"│
                    │  expires: <DATE>     │
                    └──────────┬───────────┘
                               │ Secrets Store CSI Driver
                               │ (sync on pod mount)
                               ▼
                    Kubernetes Secret
                    ┌──────────────────────┐
                    │ teastore-db-secret    │
                    │  key: db-host        │
                    │  value: "teastore-db"│
                    └──────────┬───────────┘
                               │ env: DB_HOST
                               ▼
                    ┌──────────────────────┐
                    │ teastore-persistence  │──────► teastore-db (MariaDB)
                    └──────────────────────┘
                               │
                    ┌──────────┴──────────────────────────┐
                    │              │            │          │
                    ▼              ▼            ▼          ▼
              teastore-webui  teastore-auth  teastore-  teastore-
                                            image      recommender
```

**Failure trigger:** Rotate the Key Vault secret value from `teastore-db` to `teastore-db-invalid` → persistence cannot resolve DB host → all dependent services fail.

---

## Step 1: Enable OIDC Issuer and Workload Identity on AKS

Workload Identity is required for the Secrets Store CSI Driver to authenticate against Azure Key Vault without managing credentials.

```bash
az aks update \
  --name <AKS_CLUSTER_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --enable-oidc-issuer \
  --enable-workload-identity
```

Verify OIDC issuer is active:

```bash
az aks show \
  --name <AKS_CLUSTER_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --query "oidcIssuerProfile.issuerUrl" -o tsv
```

---

## Step 2: Create Azure Key Vault

```bash
az keyvault create \
  --name <KEYVAULT_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --location <REGION> \
  --enable-rbac-authorization false
```

---

## Step 3: Store DB Host Secret with Expiration Date

Store the database hostname as a secret with an explicit expiration date.

> **Important — Timing:** Azure Key Vault fires `SecretNearExpiry` events via Event Grid approximately **30 days before expiration**. Choose your expiration window accordingly:
>
> - **Option A (recommended):** Set expiry to ~31 days from now. The `SecretNearExpiry` event fires within ~24 hours, giving you time to observe Instana's proactive detection.
> - **Option B (quick test):** Set expiry to a few hours. Only the `SecretExpired` event fires — no near-expiry warning.

```bash
# Option A: 31 days from now (triggers SecretNearExpiry soon)
EXPIRY=$(date -u -v +31d '+%Y-%m-%dT%H:%M:%SZ')

# Option B: 2 hours from now (only triggers SecretExpired)
# EXPIRY=$(date -u -v +2H '+%Y-%m-%dT%H:%M:%SZ')

az keyvault secret set \
  --vault-name <KEYVAULT_NAME> \
  --name teastore-db-host \
  --value "teastore-db" \
  --expires "$EXPIRY"
```

> **Note (Linux):** Replace `-v +31d` with `-d "+31 days"`.

Verify:

```bash
az keyvault secret show \
  --vault-name <KEYVAULT_NAME> \
  --name teastore-db-host \
  --query "{value:value, expires:attributes.expires}"
```

---

## Step 4: Configure Event Grid for Key Vault Events (Optional)

Azure Key Vault emits `SecretNearExpiry` and `SecretExpired` events via Azure Event Grid. To make these events visible to Instana, you need an Event Grid subscription that routes them to a webhook.

> **Note:** This step is optional. If Instana has a native Azure Key Vault sensor, it may poll expiration metadata directly. Check Instana's Azure integration settings first. If Instana does not natively surface Key Vault events, set up Event Grid as described below.

### 4.1 Register Event Grid Resource Provider

```bash
az provider register --namespace Microsoft.EventGrid
az provider show --namespace Microsoft.EventGrid --query "registrationState" -o tsv
# Wait until output shows "Registered"
```

### 4.2 Create Event Grid Subscription

```bash
KEYVAULT_ID=$(az keyvault show \
  --name <KEYVAULT_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --query id -o tsv)

az eventgrid event-subscription create \
  --name teastore-kv-events \
  --source-resource-id "$KEYVAULT_ID" \
  --endpoint <WEBHOOK_ENDPOINT_URL> \
  --included-event-types \
    Microsoft.KeyVault.SecretNearExpiry \
    Microsoft.KeyVault.SecretExpired
```

The webhook endpoint can be:
- An Azure Function that forwards events to Instana's Event API
- An Azure Logic App with an HTTP trigger
- Any HTTP endpoint that processes the event payload

---

## Step 5: Enable Secrets Store CSI Driver on AKS

```bash
az aks enable-addons \
  --addons azure-keyvault-secrets-provider \
  --name <AKS_CLUSTER_NAME> \
  --resource-group <RESOURCE_GROUP>
```

Verify:

```bash
kubectl get pods -n kube-system -l app=secrets-store-csi-driver
kubectl get pods -n kube-system -l app=secrets-store-provider-azure
```

Both should show `Running` status.

---

## Step 6: Configure Workload Identity

### 6.1 Create a User-Assigned Managed Identity

```bash
az identity create \
  --name teastore-identity \
  --resource-group <RESOURCE_GROUP> \
  --location <REGION>
```

### 6.2 Grant Key Vault Access

```bash
IDENTITY_CLIENT_ID=$(az identity show \
  --name teastore-identity \
  --resource-group <RESOURCE_GROUP> \
  --query clientId -o tsv)

az keyvault set-policy \
  --name <KEYVAULT_NAME> \
  --secret-permissions get \
  --spn "$IDENTITY_CLIENT_ID"
```

### 6.3 Retrieve Required IDs

```bash
AKS_OIDC_ISSUER=$(az aks show \
  --name <AKS_CLUSTER_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --query "oidcIssuerProfile.issuerUrl" -o tsv)

IDENTITY_TENANT_ID=$(az identity show \
  --name teastore-identity \
  --resource-group <RESOURCE_GROUP> \
  --query tenantId -o tsv)

echo "Client ID:  $IDENTITY_CLIENT_ID"
echo "Tenant ID:  $IDENTITY_TENANT_ID"
echo "OIDC Issuer: $AKS_OIDC_ISSUER"
```

### 6.4 Create Kubernetes Service Account

```yaml
# manifests/teastore-service-account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: teastore-sa
  namespace: default
  annotations:
    azure.workload.identity/client-id: "<IDENTITY_CLIENT_ID>"
  labels:
    azure.workload.identity/use: "true"
```

```bash
kubectl apply -f manifests/teastore-service-account.yaml
```

### 6.5 Create Federated Credential

```bash
az identity federated-credential create \
  --name teastore-federated-cred \
  --identity-name teastore-identity \
  --resource-group <RESOURCE_GROUP> \
  --issuer "$AKS_OIDC_ISSUER" \
  --subject "system:serviceaccount:default:teastore-sa" \
  --audience "api://AzureADTokenExchange"
```

---

## Step 7: Create SecretProviderClass

This resource tells the CSI Driver which Key Vault secret to mount and sync into a Kubernetes Secret.

```yaml
# manifests/secret-provider-class.yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: teastore-keyvault
  namespace: default
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "false"
    clientID: "<IDENTITY_CLIENT_ID>"
    keyvaultName: "<KEYVAULT_NAME>"
    tenantId: "<IDENTITY_TENANT_ID>"
    objects: |
      array:
        - |
          objectName: teastore-db-host
          objectType: secret
  secretObjects:
    - secretName: teastore-db-secret
      type: Opaque
      data:
        - objectName: teastore-db-host
          key: db-host
```

```bash
kubectl apply -f manifests/secret-provider-class.yaml
```

> **Note:** The Kubernetes Secret `teastore-db-secret` will not be created until a pod mounts the CSI volume. This is handled in the next step.

---

## Step 8: Modify TeaStore Persistence Deployment

The only deployment change is to `teastore-persistence`: source `DB_HOST` from the Kubernetes Secret and mount the CSI volume to trigger the sync.

### 8.1 Modified `teastore-persistence` Deployment

Replace the `teastore-persistence` Deployment section in your TeaStore YAML with:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: teastore-persistence
  labels:
    app: teastore
    run: teastore-persistence
spec:
  selector:
    matchLabels:
      app: teastore
      run: teastore-persistence
  template:
    metadata:
      labels:
        app: teastore
        run: teastore-persistence
    spec:
      serviceAccountName: teastore-sa
      containers:
        - name: teastore-persistence
          image: descartesresearch/teastore-persistence
          ports:
            - containerPort: 8080
          env:
            - name: USE_POD_IP
              value: "true"
            - name: REGISTRY_HOST
              value: "teastore-registry"
            - name: DB_HOST
              valueFrom:
                secretKeyRef:
                  name: teastore-db-secret
                  key: db-host
            - name: DB_PORT
              value: "3306"
            - name: RABBITMQ_HOST
              value: "teastore-kieker-rabbitmq"
          volumeMounts:
            - name: secrets-store
              mountPath: "/mnt/secrets-store"
              readOnly: true
      volumes:
        - name: secrets-store
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes:
              secretProviderClass: teastore-keyvault
```

**Changes compared to the original:**
1. Added `serviceAccountName: teastore-sa`
2. Changed `DB_HOST` from hardcoded `"teastore-db"` to `secretKeyRef` referencing `teastore-db-secret`
3. Added CSI volume mount (required to trigger the Key Vault → K8s Secret sync)

All other TeaStore deployments remain unchanged.

---

## Step 9: Deploy and Establish Baseline

### 9.1 Deploy Modified Stack

```bash
# Apply identity and secret provider resources
kubectl apply -f manifests/teastore-service-account.yaml
kubectl apply -f manifests/secret-provider-class.yaml

# Apply modified TeaStore deployment
kubectl apply -f teastore/teastore-ribbon-kieker.yaml
```

### 9.2 Verify Deployment

```bash
# Check all pods are running
kubectl get pods -l app=teastore

# Verify the Kubernetes Secret was created by the CSI driver
kubectl get secret teastore-db-secret -o jsonpath='{.data.db-host}' | base64 -d
# Expected output: teastore-db

# Verify TeaStore is functional
kubectl port-forward service/teastore-webui 8080:8080
# Open http://localhost:8080 and confirm the store loads with products
```

### 9.3 Check Persistence Logs

```bash
kubectl logs deploy/teastore-persistence | tail -20
# Should show successful DB connection, no errors
```

### 9.4 Establish Baseline in Instana

1. Generate load using the existing Locust setup
2. Confirm Instana is collecting traces, metrics, and events from all TeaStore services
3. Verify Instana shows a healthy service topology with `teastore-persistence` connected to the database
4. Take a screenshot of the baseline state for comparison

---

## Step 10: Execute the Experiment

### Phase 1: Proactive Detection (Observe Near-Expiry)

If you used Option A (31-day expiry), the `SecretNearExpiry` event should fire from Azure Event Grid within ~24 hours.

**Key Question:** Does Instana detect that the Azure Key Vault secret `teastore-db-host` is approaching expiration?

Document:
- Whether any alert or event appears in Instana
- The timeline of detection relative to the configured expiration date
- Whether the alert includes context about which workloads consume the secret

### Phase 2: Trigger the Failure (Reactive Detection)

Simulate a faulty secret rotation by changing the Key Vault secret to an invalid DB hostname:

```bash
# Rotate the secret to an invalid value
az keyvault secret set \
  --vault-name <KEYVAULT_NAME> \
  --name teastore-db-host \
  --value "teastore-db-invalid"
```

Now restart the persistence pod to pick up the new secret value:

```bash
kubectl rollout restart deployment teastore-persistence
```

> **Why restart is needed:** Kubernetes Secrets injected via `secretKeyRef` as environment variables are resolved at pod startup. The CSI Driver syncs the new Key Vault value to the Kubernetes Secret, but the running pod's env vars don't update until it restarts.

### Phase 2 — Expected Failure Cascade

After the pod restarts with `DB_HOST=teastore-db-invalid`:

1. `teastore-persistence` cannot resolve `teastore-db-invalid` → DNS failure or connection refused
2. `teastore-persistence` becomes unhealthy
3. All dependent services (`teastore-webui`, `teastore-auth`, `teastore-image`, `teastore-recommender`) experience errors when calling the persistence layer
4. User-facing requests return HTTP 500 errors
5. Application-level metrics degrade (response time ↑, error rate ↑, throughput ↓)

**Key Questions for Instana:**
- How quickly does Instana detect the service degradation?
- Does it correlate errors across all affected services?
- Does it identify `teastore-persistence` as the root cause?
- Does it link the failure to the Kubernetes Secret or Key Vault?
- Does it suggest remediation (pod restart, secret update)?

---

## Step 11: Evaluate and Document Results

### Evaluation Matrix

| Criteria | Question | Observation |
|---|---|---|
| **Proactive Detection** | Did Instana alert before the secret expired? | |
| **Reactive Detection** | How quickly did Instana detect the failure after rotation? | |
| **Event Correlation** | Were errors across services correlated into one incident? | |
| **Root Cause Analysis** | Did Instana identify `teastore-persistence` → DB connection as root cause? | |
| **Secret Awareness** | Did Instana link the failure to the Kubernetes Secret or Key Vault? | |
| **Remediation** | Did Instana suggest or trigger any remediation action? | |
| **ITSM: Monitoring** | Were events detected and classified correctly? | |
| **ITSM: Incident Mgmt** | Was an incident created and prioritized appropriately? | |
| **ITSM: Change Enablement** | Was the secret rotation recognized as a change event? | |
| **ITSM: Problem Mgmt** | Did Instana identify a recurring pattern or structural weakness? | |

### Evidence to Capture

- Screenshots of Instana dashboards (before, during, after failure)
- Instana alert timeline
- Service topology change visualization
- Root cause analysis output from Instana
- Any automated remediation actions or recommendations

---

## Step 12: Restore and Reset

### 12.1 Restore the Correct Secret

```bash
# Set the secret back to valid value (optionally with new expiry)
EXPIRY=$(date -u -v +31d '+%Y-%m-%dT%H:%M:%SZ')

az keyvault secret set \
  --vault-name <KEYVAULT_NAME> \
  --name teastore-db-host \
  --value "teastore-db" \
  --expires "$EXPIRY"
```

### 12.2 Restart Persistence to Pick Up Restored Secret

```bash
kubectl rollout restart deployment teastore-persistence
```

### 12.3 Verify Recovery

```bash
kubectl get pods -l run=teastore-persistence
kubectl logs deploy/teastore-persistence | tail -10
# Verify DB connection is restored

kubectl port-forward service/teastore-webui 8080:8080
# Confirm the application is functional again
```

### 12.4 Document Recovery in Instana

- Note how quickly Instana reflects the recovery
- Document whether the incident is automatically resolved
- Capture the full incident timeline from detection to resolution
