#!/bin/bash
set -euo pipefail

# ============================================================================
# Performance & Resource Utilization Experiment — DEACTIVATE
# ============================================================================
# This script deactivates the performance degradation experiment and restores
# teastore-webui and teastore-persistence to their original configurations.
# It removes the stress sidecar containers and resource limits.
# Note: Locust is NOT removed — it is managed by deploy.sh/teardown.sh.
#
# Usage: ./deactivate.sh [namespace]
# ============================================================================

NAMESPACE="${1:-teastore}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================"
echo " Performance Experiment — DEACTIVATE"
echo " Namespace: ${NAMESPACE}"
echo "============================================"
echo ""

# --- Helper: remove stress sidecar from a deployment ---
remove_stress_sidecar() {
  local DEPLOY_NAME="$1"

  echo "▸ Restoring ${DEPLOY_NAME}..."

  # Find the index of the stress container
  CONTAINERS=$(kubectl get deployment "${DEPLOY_NAME}" -n "${NAMESPACE}" \
    -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\n"}{end}')

  STRESS_INDEX=$(echo "${CONTAINERS}" | grep -n "^stress$" | cut -d: -f1 || echo "")

  if [ -z "${STRESS_INDEX}" ]; then
    echo "  ✓ No stress sidecar found in ${DEPLOY_NAME} — skipping"
    return
  fi

  # Convert 1-based line number to 0-based index
  STRESS_INDEX=$((STRESS_INDEX - 1))

  echo "  - Removing stress sidecar (container index: ${STRESS_INDEX})"
  echo "  - Removing resource limits from app container"

  kubectl patch deployment "${DEPLOY_NAME}" -n "${NAMESPACE}" --type='json' -p="[
    {
      \"op\": \"remove\",
      \"path\": \"/spec/template/spec/containers/${STRESS_INDEX}\"
    },
    {
      \"op\": \"remove\",
      \"path\": \"/spec/template/spec/containers/0/resources/limits\"
    }
  ]"

  echo "  ✓ ${DEPLOY_NAME} restored"
}

# --- Step 1: Remove stress sidecars ---
remove_stress_sidecar "teastore-webui"
echo ""
remove_stress_sidecar "teastore-persistence"

# --- Step 2: Wait for rollout ---
echo ""
echo "▸ Waiting for teastore-webui rollout..."
kubectl rollout status deployment/teastore-webui -n "${NAMESPACE}" --timeout=120s

echo "▸ Waiting for teastore-persistence rollout..."
kubectl rollout status deployment/teastore-persistence -n "${NAMESPACE}" --timeout=120s

# --- Step 3: Verify ---
echo ""
echo "▸ Verifying restoration..."

# Check webui
WEBUI_COUNT=$(kubectl get pods -l run=teastore-webui -n "${NAMESPACE}" \
  -o jsonpath='{.items[0].spec.containers[*].name}' 2>/dev/null | wc -w | tr -d ' ')
echo "  ✓ teastore-webui containers: ${WEBUI_COUNT} (expected: 1)"

WEBUI_STATUS=$(kubectl get pods -l run=teastore-webui -n "${NAMESPACE}" \
  -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
echo "  ✓ teastore-webui pod status: ${WEBUI_STATUS}"

# Check persistence
PERSIST_COUNT=$(kubectl get pods -l run=teastore-persistence -n "${NAMESPACE}" \
  -o jsonpath='{.items[0].spec.containers[*].name}' 2>/dev/null | wc -w | tr -d ' ')
echo "  ✓ teastore-persistence containers: ${PERSIST_COUNT} (expected: 1)"

PERSIST_STATUS=$(kubectl get pods -l run=teastore-persistence -n "${NAMESPACE}" \
  -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
echo "  ✓ teastore-persistence pod status: ${PERSIST_STATUS}"

echo ""
echo "============================================"
echo " ✓ Experiment DEACTIVATED"
echo ""
echo " teastore-webui and teastore-persistence"
echo " are restored to their original configurations."
echo "============================================"
