#!/bin/bash
set -euo pipefail

# ============================================================================
# Performance & Resource Utilization Experiment — ACTIVATE
# ============================================================================
# This script activates the performance degradation experiment on a running
# TeaStore deployment. It sets resource limits on target deployments and
# injects stress sidecar containers into teastore-webui and
# teastore-persistence.
#
# Prerequisites:
#   - TeaStore deployed and running in the cluster (incl. Locust)
#   - Metrics Server available (kubectl top works)
#   - Instana agent deployed
#
# Usage: ./activate.sh [namespace]
# ============================================================================

NAMESPACE="${1:-teastore}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/manifests"

echo "============================================"
echo " Performance Experiment — ACTIVATE"
echo " Namespace: ${NAMESPACE}"
echo "============================================"
echo ""

# --- Step 1: Apply resource limits + stress sidecar to teastore-webui ---
echo ""
echo "▸ Patching teastore-webui..."
echo "  - Adding resource limits (cpu: 500m, memory: 1500Mi)"
echo "  - Injecting stress sidecar container"

# Check if stress sidecar is already present
WEBUI_CONTAINERS=$(kubectl get deployment teastore-webui -n "${NAMESPACE}" \
  -o jsonpath='{.spec.template.spec.containers[*].name}' 2>/dev/null)

if echo "${WEBUI_CONTAINERS}" | grep -q "stress"; then
  echo "  ✓ Stress sidecar already injected in teastore-webui"
else
  kubectl patch deployment teastore-webui -n "${NAMESPACE}" \
    --type=strategic \
    --patch-file "${MANIFESTS_DIR}/stress-patch-webui.yaml"
  echo "  ✓ teastore-webui patched"
fi

# --- Step 2: Apply resource limits + stress sidecar to teastore-persistence ---
echo ""
echo "▸ Patching teastore-persistence..."
echo "  - Adding resource limits (cpu: 500m, memory: 1500Mi)"
echo "  - Injecting stress sidecar container"

PERSISTENCE_CONTAINERS=$(kubectl get deployment teastore-persistence -n "${NAMESPACE}" \
  -o jsonpath='{.spec.template.spec.containers[*].name}' 2>/dev/null)

if echo "${PERSISTENCE_CONTAINERS}" | grep -q "stress"; then
  echo "  ✓ Stress sidecar already injected in teastore-persistence"
else
  kubectl patch deployment teastore-persistence -n "${NAMESPACE}" \
    --type=strategic \
    --patch-file "${MANIFESTS_DIR}/stress-patch-persistence.yaml"
  echo "  ✓ teastore-persistence patched"
fi

# --- Step 3: Wait for rollout ---
echo ""
echo "▸ Waiting for teastore-webui rollout..."
kubectl rollout status deployment/teastore-webui -n "${NAMESPACE}" --timeout=120s

echo "▸ Waiting for teastore-persistence rollout..."
kubectl rollout status deployment/teastore-persistence -n "${NAMESPACE}" --timeout=120s

# --- Step 4: Verify ---
echo ""
echo "▸ Verifying setup..."

# Check webui pod containers
WEBUI_COUNT=$(kubectl get pods -l run=teastore-webui -n "${NAMESPACE}" \
  -o jsonpath='{.items[0].spec.containers[*].name}' 2>/dev/null | wc -w | tr -d ' ')
echo "  ✓ teastore-webui containers: ${WEBUI_COUNT} (expected: 2)"

# Check persistence pod containers
PERSIST_COUNT=$(kubectl get pods -l run=teastore-persistence -n "${NAMESPACE}" \
  -o jsonpath='{.items[0].spec.containers[*].name}' 2>/dev/null | wc -w | tr -d ' ')
echo "  ✓ teastore-persistence containers: ${PERSIST_COUNT} (expected: 2)"

# Check pod status
WEBUI_STATUS=$(kubectl get pods -l run=teastore-webui -n "${NAMESPACE}" \
  -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
echo "  ✓ teastore-webui pod status: ${WEBUI_STATUS}"

PERSIST_STATUS=$(kubectl get pods -l run=teastore-persistence -n "${NAMESPACE}" \
  -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
echo "  ✓ teastore-persistence pod status: ${PERSIST_STATUS}"

# Check Locust status
LOCUST_STATUS=$(kubectl get pods -l app=locust -n "${NAMESPACE}" \
  -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
echo "  ✓ Locust pod status: ${LOCUST_STATUS}"

echo ""
echo "============================================"
echo " ✓ Experiment ACTIVATED"
echo ""
echo " Stress sidecars injected into:"
echo "   - teastore-webui"
echo "   - teastore-persistence"
echo ""
echo " Access the Locust UI:"
echo "   kubectl port-forward svc/locust 8089:8089 -n ${NAMESPACE}"
echo "   → http://localhost:8089"
echo "   → Start with 50 users, spawn rate 5"
echo ""
echo " Monitor resource usage:"
echo "   watch kubectl top pods -n ${NAMESPACE}"
echo "============================================"
