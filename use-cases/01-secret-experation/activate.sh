#!/bin/bash
set -euo pipefail

# ============================================================================
# Secret Expiration Experiment — ACTIVATE
# ============================================================================
# This script activates the secret expiration experiment on a running TeaStore
# deployment. It sets up Azure Key Vault with a secret, configures Workload
# Identity access, and patches teastore-persistence to source DB_HOST from a
# Kubernetes Secret synced via the CSI Driver.
#
# Prerequisites:
#   - TeaStore deployed and running in the cluster
#   - Secrets Store CSI Driver enabled on AKS
#   - Azure CLI logged in with appropriate permissions
#
# Usage: ./activate.sh [namespace]
# ============================================================================

NAMESPACE="${1:-teastore}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/manifests"

# Azure configuration
RESOURCE_GROUP="<YOUR_RESOURCE_GROUP>"
LOCATION="westeurope"
KEYVAULT_NAME="<YOUR_KEYVAULT_NAME>"
SECRET_NAME="teastore-db-host"
SECRET_VALUE="teastore-db"
IDENTITY_NAME="teastore-workload-identity"
AKS_CLUSTER_NAME="<YOUR_AKS_CLUSTER_NAME>"

echo "============================================"
echo " Secret Expiration Experiment — ACTIVATE"
echo " Namespace: ${NAMESPACE}"
echo "============================================"
echo ""

# --- Step 1: Set up Azure Key Vault and Secret ---
echo "▸ Ensuring Azure Key Vault '${KEYVAULT_NAME}' exists..."
if az keyvault show --name "${KEYVAULT_NAME}" &>/dev/null; then
  echo "  ✓ Key Vault already exists"
elif az keyvault list-deleted --query "[?name=='${KEYVAULT_NAME}']" -o tsv 2>/dev/null | grep -q "${KEYVAULT_NAME}"; then
  echo "  ⟳ Key Vault found in soft-deleted state, recovering..."
  az keyvault recover --name "${KEYVAULT_NAME}" --output none
  echo "  ✓ Key Vault recovered"
  # Wait a moment for recovery to complete
  sleep 5
else
  az keyvault create \
    --name "${KEYVAULT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --output none
  echo "  ✓ Key Vault created"
fi

echo "▸ Setting secret '${SECRET_NAME}' in Key Vault (with immediate expiration)..."
EXPIRY_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
az keyvault secret set \
  --vault-name "${KEYVAULT_NAME}" \
  --name "${SECRET_NAME}" \
  --value "${SECRET_VALUE}" \
  --expires "${EXPIRY_TIME}" \
  --output none
echo "  ✓ Secret set: ${SECRET_NAME}=${SECRET_VALUE}"
echo "  ✓ Expiration set to: ${EXPIRY_TIME} (already expired)"

# --- Step 2: Ensure Managed Identity and access policy ---
echo ""
echo "▸ Ensuring Managed Identity '${IDENTITY_NAME}' exists..."
IDENTITY_CLIENT_ID=$(az identity show \
  --name "${IDENTITY_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query clientId -o tsv 2>/dev/null || echo "")

if [ -z "${IDENTITY_CLIENT_ID}" ]; then
  az identity create \
    --name "${IDENTITY_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --output none
  IDENTITY_CLIENT_ID=$(az identity show \
    --name "${IDENTITY_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query clientId -o tsv)
  echo "  ✓ Managed Identity created (clientId: ${IDENTITY_CLIENT_ID})"
else
  echo "  ✓ Managed Identity exists (clientId: ${IDENTITY_CLIENT_ID})"
fi

echo "▸ Setting Key Vault access policy for identity..."
az keyvault set-policy \
  --name "${KEYVAULT_NAME}" \
  --spn "${IDENTITY_CLIENT_ID}" \
  --secret-permissions get list \
  --output none
echo "  ✓ Access policy set"

# --- Step 3: Ensure federated credential for namespace ---
echo "▸ Ensuring federated credential for namespace '${NAMESPACE}'..."
AKS_OIDC_ISSUER=$(az aks show \
  --name "${AKS_CLUSTER_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "oidcIssuerProfile.issuerUrl" -o tsv)

FED_CRED_NAME="teastore-sa-${NAMESPACE}"
if az identity federated-credential show \
  --name "${FED_CRED_NAME}" \
  --identity-name "${IDENTITY_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  echo "  ✓ Federated credential already exists"
else
  az identity federated-credential create \
    --name "${FED_CRED_NAME}" \
    --identity-name "${IDENTITY_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --issuer "${AKS_OIDC_ISSUER}" \
    --subject "system:serviceaccount:${NAMESPACE}:teastore-sa" \
    --audiences "api://AzureADTokenExchange" \
    --output none
  echo "  ✓ Federated credential created"
fi

# --- Step 4: Update ServiceAccount with correct client ID ---
echo ""
echo "▸ Updating ServiceAccount manifest with client ID..."
sed -i.bak "s|azure.workload.identity/client-id: .*|azure.workload.identity/client-id: \"${IDENTITY_CLIENT_ID}\"|" \
  "${MANIFESTS_DIR}/teastore-service-account.yaml"
rm -f "${MANIFESTS_DIR}/teastore-service-account.yaml.bak"

# Update SecretProviderClass with correct client ID
sed -i.bak "s|clientID: .*|clientID: \"${IDENTITY_CLIENT_ID}\"|" \
  "${MANIFESTS_DIR}/secret-provider-class.yaml"
rm -f "${MANIFESTS_DIR}/secret-provider-class.yaml.bak"

# --- Step 5: Apply Kubernetes resources ---
echo "▸ Applying ServiceAccount (teastore-sa)..."
kubectl apply -f "${MANIFESTS_DIR}/teastore-service-account.yaml" -n "${NAMESPACE}"

echo "▸ Applying SecretProviderClass (teastore-keyvault)..."
kubectl apply -f "${MANIFESTS_DIR}/secret-provider-class.yaml" -n "${NAMESPACE}"

# --- Step 6: Patch teastore-persistence deployment ---
echo ""
echo "▸ Patching teastore-persistence deployment..."
echo "  - Adding serviceAccountName: teastore-sa"
echo "  - Changing DB_HOST from hardcoded value to secretKeyRef"
echo "  - Adding CSI volume mount"

kubectl patch deployment teastore-persistence -n "${NAMESPACE}" --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/serviceAccountName",
    "value": "teastore-sa"
  },
  {
    "op": "add",
    "path": "/spec/template/spec/volumes",
    "value": [
      {
        "name": "secrets-store",
        "csi": {
          "driver": "secrets-store.csi.k8s.io",
          "readOnly": true,
          "volumeAttributes": {
            "secretProviderClass": "teastore-keyvault"
          }
        }
      }
    ]
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/volumeMounts",
    "value": [
      {
        "name": "secrets-store",
        "mountPath": "/mnt/secrets-store",
        "readOnly": true
      }
    ]
  }
]'

# Patch DB_HOST env var: find its index and replace it
DB_HOST_INDEX=$(kubectl get deployment teastore-persistence -n "${NAMESPACE}" \
  -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}{"\n"}{end}' \
  | grep -n "^DB_HOST$" | cut -d: -f1)

if [ -z "${DB_HOST_INDEX}" ]; then
  echo "  ✗ ERROR: DB_HOST env var not found in teastore-persistence"
  exit 1
fi

# Convert 1-based line number to 0-based index
DB_HOST_INDEX=$((DB_HOST_INDEX - 1))

kubectl patch deployment teastore-persistence -n "${NAMESPACE}" --type='json' -p="[
  {
    \"op\": \"replace\",
    \"path\": \"/spec/template/spec/containers/0/env/${DB_HOST_INDEX}\",
    \"value\": {
      \"name\": \"DB_HOST\",
      \"valueFrom\": {
        \"secretKeyRef\": {
          \"name\": \"teastore-db-secret\",
          \"key\": \"db-host\"
        }
      }
    }
  }
]"

# --- Step 7: Wait for rollout ---
echo ""
echo "▸ Waiting for teastore-persistence rollout..."
kubectl rollout status deployment/teastore-persistence -n "${NAMESPACE}" --timeout=120s

# --- Step 8: Verify ---
echo ""
echo "▸ Verifying setup..."

# Check K8s secret was synced
DB_HOST_VALUE=$(kubectl get secret teastore-db-secret -n "${NAMESPACE}" \
  -o jsonpath='{.data.db-host}' 2>/dev/null | base64 -d 2>/dev/null || echo "NOT_FOUND")

if [ "${DB_HOST_VALUE}" = "NOT_FOUND" ]; then
  echo "  ✗ WARNING: Kubernetes Secret 'teastore-db-secret' not found."
  echo "    The CSI Driver may need a moment to sync. Check again in ~30s."
else
  echo "  ✓ K8s Secret 'teastore-db-secret' synced: db-host=${DB_HOST_VALUE}"
fi

# Check pod is running
POD_STATUS=$(kubectl get pods -l run=teastore-persistence -n "${NAMESPACE}" \
  -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
echo "  ✓ teastore-persistence pod status: ${POD_STATUS}"

echo ""
echo "============================================"
echo " ✓ Experiment ACTIVATED"
echo ""
echo " DB_HOST is now sourced from:"
echo "   Azure Key Vault → K8s Secret → env var"
echo ""
echo " To trigger the failure:"
echo "   az keyvault secret set \\"
echo "     --vault-name <YOUR_KEYVAULT_NAME> \\"
echo "     --name teastore-db-host \\"
echo "     --value \"teastore-db-invalid\""
echo ""
echo "   kubectl rollout restart deployment teastore-persistence"
echo "============================================"
