#!/bin/bash
set -euo pipefail

# ============================================================================
# Secret Expiration Experiment — DEACTIVATE
# ============================================================================
# This script deactivates the secret expiration experiment and restores
# teastore-persistence to its original configuration with a hardcoded DB_HOST.
#
# Usage: ./deactivate.sh [namespace]
# ============================================================================

NAMESPACE="${1:-teastore}"

echo "============================================"
echo " Secret Expiration Experiment — DEACTIVATE"
echo " Namespace: ${NAMESPACE}"
echo "============================================"
echo ""

# --- Step 1: Patch teastore-persistence back to original ---
echo "▸ Restoring teastore-persistence deployment..."
echo "  - Removing serviceAccountName"
echo "  - Setting DB_HOST back to hardcoded 'teastore-db'"
echo "  - Removing CSI volume and volume mount"

# Find DB_HOST env var index
DB_HOST_INDEX=$(kubectl get deployment teastore-persistence -n "${NAMESPACE}" \
  -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}{"\n"}{end}' \
  | grep -n "^DB_HOST$" | cut -d: -f1)

if [ -z "${DB_HOST_INDEX}" ]; then
  echo "  ✗ ERROR: DB_HOST env var not found in teastore-persistence"
  exit 1
fi

DB_HOST_INDEX=$((DB_HOST_INDEX - 1))

# Apply all patches in one call to trigger a single rollout
kubectl patch deployment teastore-persistence -n "${NAMESPACE}" --type='json' -p="[
  {
    \"op\": \"remove\",
    \"path\": \"/spec/template/spec/serviceAccountName\"
  },
  {
    \"op\": \"replace\",
    \"path\": \"/spec/template/spec/containers/0/env/${DB_HOST_INDEX}\",
    \"value\": {
      \"name\": \"DB_HOST\",
      \"value\": \"teastore-db\"
    }
  },
  {
    \"op\": \"remove\",
    \"path\": \"/spec/template/spec/containers/0/volumeMounts\"
  },
  {
    \"op\": \"remove\",
    \"path\": \"/spec/template/spec/volumes\"
  }
]"

# --- Step 2: Wait for rollout ---
echo ""
echo "▸ Waiting for teastore-persistence rollout..."
kubectl rollout status deployment/teastore-persistence -n "${NAMESPACE}" --timeout=120s

# --- Step 3: Clean up K8s resources ---
echo ""
echo "▸ Cleaning up experiment resources..."

kubectl delete secret teastore-db-secret -n "${NAMESPACE}" --ignore-not-found=true
echo "  ✓ Deleted K8s Secret 'teastore-db-secret'"

kubectl delete secretproviderclass teastore-keyvault -n "${NAMESPACE}" --ignore-not-found=true
echo "  ✓ Deleted SecretProviderClass 'teastore-keyvault'"

kubectl delete serviceaccount teastore-sa -n "${NAMESPACE}" --ignore-not-found=true
echo "  ✓ Deleted ServiceAccount 'teastore-sa'"

# --- Step 4: Verify ---
echo ""
echo "▸ Verifying restoration..."

POD_STATUS=$(kubectl get pods -l run=teastore-persistence -n "${NAMESPACE}" \
  -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
echo "  ✓ teastore-persistence pod status: ${POD_STATUS}"

DB_HOST_VALUE=$(kubectl get deployment teastore-persistence -n "${NAMESPACE}" \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="DB_HOST")].value}' 2>/dev/null)
echo "  ✓ DB_HOST restored to: ${DB_HOST_VALUE}"

echo ""
echo "============================================"
echo " ✓ Experiment DEACTIVATED"
echo ""
echo " teastore-persistence is back to its"
echo " original configuration with hardcoded"
echo " DB_HOST=teastore-db"
echo ""
echo " Note: Azure Key Vault resources (vault,"
echo " secret, identity) are NOT deleted."
echo " Remove them manually if no longer needed."
echo "============================================"
