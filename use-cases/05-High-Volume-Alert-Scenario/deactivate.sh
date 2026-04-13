#!/bin/bash
set -euo pipefail

# ============================================================================
# High-Volume Alert Scenario (200 Failing Pods) — DEACTIVATE
# ============================================================================
# This script removes the alert-flood Deployment, which deletes all
# 200 failing pods from the cluster.
#
# Prerequisites:
#   - Experiment activated via activate.sh
# ============================================================================

NAMESPACE="${1:-teastore}"

echo "==================================================="
echo " High-Volume Alert Scenario — DEACTIVATE"
echo " Namespace: ${NAMESPACE}"
echo "==================================================="
echo ""

# 1. Delete the Alert Flood
echo "▸ Deleting the 'alert-flood' Deployment..."
kubectl delete -f "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/manifests/alert-flood.yaml" -n "${NAMESPACE}" --ignore-not-found

# 2. Status
echo ""
echo "======================================================================"
echo " ✓ Alert Flood Experiment Deactivated"
echo "======================================================================"
echo " The failing pods are being terminated."
echo " Instana should automatically resolve the corresponding incident."
