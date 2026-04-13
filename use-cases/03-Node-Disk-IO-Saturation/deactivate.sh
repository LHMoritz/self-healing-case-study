#!/bin/bash
set -euo pipefail

# ============================================================================
# Node Disk IO Saturation — DEACTIVATE
# ============================================================================
# This script reverts the changes made by activate.sh, ending the experiment.
#
# Usage: ./deactivate.sh [namespace]
# ============================================================================

NAMESPACE="${1:-teastore}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================"
echo " Node Disk IO Saturation — DEACTIVATE"
echo " Namespace: ${NAMESPACE}"
echo "============================================"
echo ""

# 1. Delete DaemonSet
echo "▸ Deleting the node-io-stress DaemonSet..."
kubectl delete -f "${SCRIPT_DIR}/manifests/io-stress-daemonset.yaml" -n "${NAMESPACE}" --ignore-not-found

# 2. Find Node running teastore-db to unlabel
echo ""
echo "▸ Locating target node (hosting teastore-db)..."
TARGET_NODE=$(kubectl get pod -l run=teastore-db -n "${NAMESPACE}" -o jsonpath='{.items[0].spec.nodeName}')

if [ -n "$TARGET_NODE" ]; then
  # 3. Remove Node Label
  echo "▸ Removing IO stress label from node ${TARGET_NODE}..."
  kubectl label node "${TARGET_NODE}" teastore-experiment-io-stress- || true
else
    echo "⚠️ Warning: Could not find node running teastore-db. Trying to unlabel all nodes..."
    kubectl label node -l teastore-experiment-io-stress=true teastore-experiment-io-stress- || true
fi

echo ""
echo "============================================"
echo " ✓ IO Saturation Experiment Deactivated"
echo "============================================"
