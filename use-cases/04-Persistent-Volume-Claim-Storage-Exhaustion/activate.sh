#!/bin/bash
set -euo pipefail

# ============================================================================
# Persistent Volume Claim Storage Exhaustion — ACTIVATE
# ============================================================================
# This script applies a 1Gi PersistentVolumeClaim and patches the teastore-db
# to use it, while simultaneously injecting a sidecar to fill the volume.
#
# Prerequisites:
#   - Locust is already running and generating traffic.
# ============================================================================

NAMESPACE="${1:-teastore}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==================================================="
echo " PVC Storage Exhaustion — ACTIVATE"
echo " Namespace: ${NAMESPACE}"
echo "==================================================="
echo ""

# 1. Apply PVC
echo "▸ Deploying 1Gi PVC for teastore-db..."
kubectl apply -f "${SCRIPT_DIR}/manifests/db-pvc.yaml" -n "${NAMESPACE}"

# 2. Patch Deployment
echo ""
echo "▸ Patching teastore-db to use PVC and injecting volume-filler sidecar..."
kubectl patch deployment teastore-db -n "${NAMESPACE}" --patch-file "${SCRIPT_DIR}/manifests/storage-exhaustion-sidecar.yaml"

# 3. Wait for rollout
echo ""
echo "▸ Waiting for the patched teastore-db pod to start..."
kubectl rollout status deployment/teastore-db -n "${NAMESPACE}" --timeout=120s

# 4. Status
echo ""
echo "======================================================================"
echo " ✓ PVC Exhaustion Experiment Activated"
echo "======================================================================"
echo " The sidecar container ('volume-filler') is now writing 950MB"
echo " of dummy data to the MariaDB volume. Within seconds, the PVC"
echo " will reach 100% capacity."
echo ""
echo " You can watch the filler progress here:"
echo "   kubectl logs -l run=teastore-db -c volume-filler -n ${NAMESPACE} -f"
echo ""
echo " Observe Instana for:"
echo " 1) PVC Capacity Exhaustion Alert"
echo " 2) teastore-persistence exceptions (HTTP 500s in Locust) correlated to the full volume."
echo "======================================================================"
