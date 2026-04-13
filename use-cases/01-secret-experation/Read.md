# Use Case 01 — Secret Expiration Simulation
## AKS + TeaStore + Azure Key Vault

---

## 1. Purpose

This experiment evaluates whether Instana, as an AI-agent-based observability platform, can:

1. **Proactively detect** that a secret in Azure Key Vault is approaching its expiration date — before any service disruption occurs.
2. **Reactively detect** the cascading service failures caused by a rotated or invalid secret.
3. **Correlate** infrastructure-level events (Key Vault, Kubernetes Secret) with application-level symptoms (connection errors, HTTP 500s).
4. **Identify the root cause** of a multi-service outage originating from a single configuration change.

The experiment is conducted in an AKS-based TeaStore microservice environment that structurally reflects enterprise platform characteristics.

---

## 2. Architecture

### 2.1 High-Level Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Azure Cloud                                  │
│                                                                     │
│   ┌───────────────────────┐       ┌────────────────────────────┐   │
│   │   Azure Key Vault     │       │   Azure Event Grid         │   │
│   │   <YOUR_KEYVAULT_NAME>  │──────▶│   SecretNearExpiry /       │   │
│   │                       │       │   SecretExpired events     │   │
│   │   Secret:             │       └────────────────────────────┘   │
│   │     teastore-db-host  │                                        │
│   │     value: teastore-db│                                        │
│   │     expires: <DATE>   │                                        │
│   └───────────┬───────────┘                                        │
│               │                                                     │
│               │ Workload Identity (OIDC federation)                 │
│               │                                                     │
│   ┌───────────▼──────────────────────────────────────────────────┐ │
│   │                    AKS Cluster (<YOUR_CLUSTER_NAME>)                  │ │
│   │                                                               │ │
│   │   ┌─────────────────────────────────────────────────────┐    │ │
│   │   │            Secrets Store CSI Driver                  │    │ │
│   │   │   Polls Key Vault → syncs to K8s Secret (~2 min)   │    │ │
│   │   └──────────────────────┬──────────────────────────────┘    │ │
│   │                          │                                    │ │
│   │                          ▼                                    │ │
│   │   ┌──────────────────────────────┐                           │ │
│   │   │  K8s Secret:                 │                           │ │
│   │   │   teastore-db-secret         │                           │ │
│   │   │   key: db-host               │                           │ │
│   │   │   value: "teastore-db"       │                           │ │
│   │   └──────────────┬───────────────┘                           │ │
│   │                  │ env: DB_HOST (secretKeyRef)                │ │
│   │                  ▼                                            │ │
│   │   ┌────────────────────────┐     ┌──────────────────────┐   │ │
│   │   │ teastore-persistence   │────▶│ teastore-db (MariaDB)│   │ │
│   │   │ (DB_HOST from Secret)  │     │                      │   │ │
│   │   └────────────┬───────────┘     └──────────────────────┘   │ │
│   │                │                                              │ │
│   │       ┌────────┼────────┬──────────┐                         │ │
│   │       ▼        ▼        ▼          ▼                         │ │
│   │   webui     auth     image    recommender                    │ │
│   │                                                               │ │
│   └───────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 Components

| Component | Role |
|---|---|
| **Azure Key Vault** (`<YOUR_KEYVAULT_NAME>`) | Stores the `teastore-db-host` secret with an explicit expiration date |
| **Secrets Store CSI Driver** | Mounts Key Vault secrets into pods and syncs them into Kubernetes Secrets |
| **Workload Identity** | Authenticates the pod against Key Vault using OIDC federation (no stored credentials) |
| **K8s Secret** (`teastore-db-secret`) | Kubernetes-native secret created by the CSI Driver, consumed as `DB_HOST` env var |
| **teastore-persistence** | The only modified TeaStore service — sources `DB_HOST` from the K8s Secret instead of a hardcoded value |
| **teastore-db** | MariaDB database, addressed by hostname `teastore-db` via K8s Service |
| **All other TeaStore services** | Unmodified — they depend on `teastore-persistence` and are affected by its failure |
| **Azure Event Grid** | Emits `SecretNearExpiry` and `SecretExpired` events from Key Vault (optional integration) |

### 2.3 Identity Chain

```
teastore-persistence pod
  └── ServiceAccount: teastore-sa
        └── annotation: azure.workload.identity/client-id
              └── UAMI: teastore-identity (federated credential)
                    └── Key Vault access policy: get secrets
                          └── Key Vault: <YOUR_KEYVAULT_NAME>
```

---

## 3. What Was Modified

**Only the `teastore-persistence` deployment is modified.** All other TeaStore services remain unchanged. The modification consists of three changes:

1. **`serviceAccountName: teastore-sa`** — binds the pod to the Workload Identity chain
2. **`DB_HOST` sourced from `secretKeyRef`** — instead of a hardcoded `"teastore-db"` value, it references the K8s Secret synced from Key Vault
3. **CSI volume mount** — mounts the CSI volume at `/mnt/secrets-store` to trigger and maintain the Key Vault → K8s Secret sync

No application code is changed. The stock `descartesresearch/teastore-persistence` image is used as-is.

---

## 4. Experiment Scenario

### Phase 1: Proactive Detection (Near-Expiry)

The secret in Key Vault is created with an expiration date ~31 days in the future. Azure Key Vault emits a `SecretNearExpiry` event via Event Grid approximately 30 days before expiration.

**Evaluation:** Can Instana detect and alert on the approaching expiration before any service impact occurs?

### Phase 2: Reactive Detection (Failure Trigger)

The Key Vault secret is rotated to an invalid value (`teastore-db-invalid`), and the persistence pod is restarted to pick up the change:

```bash
# 1. Rotate secret to invalid value
az keyvault secret set \
  --vault-name <YOUR_KEYVAULT_NAME> \
  --name teastore-db-host \
  --value "teastore-db-invalid"

# 2. Restart pod to pick up new value
kubectl rollout restart deployment teastore-persistence
```

### Expected Failure Cascade

```
teastore-db-host = "teastore-db-invalid"
        │
        ▼
teastore-persistence: DNS resolution fails → connection error
        │
        ▼
All dependent services (webui, auth, image, recommender):
  HTTP calls to persistence fail → HTTP 500 responses
        │
        ▼
User-facing impact: TeaStore becomes non-functional
```

**Evaluation:** How quickly does Instana detect the degradation? Does it correlate errors across services and identify `teastore-persistence` → DB connection as root cause?

### Phase 3: Recovery

```bash
# 1. Restore valid secret
az keyvault secret set \
  --vault-name <YOUR_KEYVAULT_NAME> \
  --name teastore-db-host \
  --value "teastore-db"

# 2. Restart pod
kubectl rollout restart deployment teastore-persistence
```

---

## 5. Scripts

| Script | Purpose |
|---|---|
| `activate.sh` | Patches `teastore-persistence` to source `DB_HOST` from Key Vault. Applies ServiceAccount, SecretProviderClass, and CSI volume. |
| `deactivate.sh` | Reverts `teastore-persistence` to hardcoded `DB_HOST=teastore-db`. Removes all experiment K8s resources. |

Both scripts accept an optional namespace argument (`./activate.sh [namespace]`, defaults to `default`).

---

## 6. Manifests

| File | Content |
|---|---|
| `manifests/teastore-service-account.yaml` | K8s ServiceAccount `teastore-sa` with Workload Identity annotation |
| `manifests/secret-provider-class.yaml` | SecretProviderClass linking Key Vault secret to K8s Secret |
| `manifests/teastore-ribbon-kieker-modified.yaml` | Full TeaStore deployment with modified persistence (for reference) |

---

## 7. Evaluation Criteria

| Criteria | Question |
|---|---|
| **Proactive Detection** | Did Instana alert before the secret expired? |
| **Reactive Detection** | How quickly did Instana detect the failure after rotation? |
| **Event Correlation** | Were errors across services correlated into one incident? |
| **Root Cause Analysis** | Did Instana identify `teastore-persistence` → DB connection as root cause? |
| **Secret Awareness** | Did Instana link the failure to the Kubernetes Secret or Key Vault? |
| **Remediation** | Did Instana suggest or trigger any remediation action? |

### ITSM Process Mapping

| ITSM Practice | Relevance |
|---|---|
| **Monitoring & Event Management** | Proactive risk detection via secret expiration metadata |
| **Incident Management** | Reactive failure handling and automated incident creation |
| **Change Enablement** | Secret rotation recognized as a change event |
| **Problem Management** | Identification of recurring credential lifecycle issues |

---

## 8. Key Technical Details

### Secret Sync Timing

- **Key Vault → K8s Secret:** The CSI Driver polls every ~2 minutes. Changes in Key Vault are reflected in the K8s Secret within this interval.
- **K8s Secret → Pod env var:** Environment variables are resolved at pod startup only. A `kubectl rollout restart` is required for the pod to pick up a new secret value.

### Azure Key Vault Event Timing

- **`SecretNearExpiry`:** Fires ~30 days before the expiration date.
- **`SecretExpired`:** Fires when the expiration date is reached.
- These events are emitted via Azure Event Grid and are not pushed to Instana directly. An Event Grid subscription with a webhook is needed to forward them.

### Why DB_HOST Instead of a Password

The stock TeaStore images do not support database password configuration via environment variables. `DB_HOST` is a supported environment variable for `teastore-persistence` and produces the same observable failure pattern (cascading service errors) without requiring application code changes.
