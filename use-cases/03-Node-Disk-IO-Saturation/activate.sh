#!/bin/bash
set -euo pipefail

# ============================================================================
# Node Disk IO Saturation — ACTIVATE
# ============================================================================
# This script deploys a Locust load generator, finds the node hosting the
# teastore-db pod, labels it, and deploys a DaemonSet that saturates its
# disk IO using polinux/stress.
#
# Usage: ./activate.sh [namespace]
# ============================================================================

NAMESPACE="${1:-teastore}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================"
echo " Node Disk IO Saturation — ACTIVATE"
echo " Namespace: ${NAMESPACE}"
echo "============================================"
echo ""

# 1. Find Node running teastore-db
echo ""
echo "▸ Locating target node for IO stress (hosting teastore-db)..."
TARGET_NODE=$(kubectl get pod -l run=teastore-db -n "${NAMESPACE}" -o jsonpath='{.items[0].spec.nodeName}')

if [ -z "$TARGET_NODE" ]; then
  echo "❌ Error: Could not find node running teastore-db in namespace ${NAMESPACE}"
  exit 1
fi

echo "  ✓ Found teastore-db running on node: ${TARGET_NODE}"

# 2. Label Node
echo ""
echo "▸ Labeling node ${TARGET_NODE} to receive the IO stressor..."
kubectl label node "${TARGET_NODE}" teastore-experiment-io-stress=true --overwrite

# 3. Deploy IO Stressor
echo ""
echo "▸ Deploying the node-io-stress DaemonSet..."
kubectl apply -f "${SCRIPT_DIR}/manifests/io-stress-daemonset.yaml" -n "${NAMESPACE}"

# 4. Wait for rollout
echo ""
echo "▸ Waiting for the IO stressor pod to start..."
kubectl rollout status daemonset/node-io-stress -n "${NAMESPACE}" --timeout=120s

# 5. Status
echo ""
echo "======================================================================"
echo " ✓ IO Saturation Experiment Activated"
echo ""
echo " 1. Start the Locust test (e.g. 50 users, rate 5) via the web UI"
echo "    Port-forward: kubectl port-forward svc/locust 8089:8089 -n ${NAMESPACE}"
echo ""
echo " 2. Observe the node's disk IO increasing: "
echo "    kubectl top node ${TARGET_NODE}"
echo ""
echo " 3. Check Instana dashboards for Node events and corresponding"
echo "    latency spikes on teastore-db and teastore-persistence."
echo ""
echo " To deactivate, run: ./deactivate.sh"
echo "======================================================================"
