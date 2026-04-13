#!/bin/bash
set -euo pipefail

# ============================================================================
# High-Volume Alert Scenario (200 Failing Pods) — ACTIVATE
# ============================================================================
# This script deploys a simple Deployment configured with 200 replicas.
# The container runs an 'exit 1' command immediately, forcing 200 pods
# into a massive, simultaneous CrashLoopBackOff state.
# ============================================================================

NAMESPACE="${1:-teastore}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==================================================="
echo " High-Volume Alert Scenario — ACTIVATE"
echo " Namespace: ${NAMESPACE}"
echo "==================================================="
echo ""

# 1. Deploy the Alert Flood
echo "▸ Deploying the 'alert-flood' Deployment (200 replicas)..."
kubectl apply -f "${SCRIPT_DIR}/manifests/alert-flood.yaml" -n "${NAMESPACE}"

# 2. Status
echo ""
echo "======================================================================"
echo " ✓ Alert Flood Experiment Activated"
echo "======================================================================"
echo " Kubernetes is now attempting to schedule 200 pods that will"
echo " instantly fail. This will trigger hundreds of CrashLoopBackOff"
echo " events."
echo ""
echo " You can watch the pods failing here:"
echo "   kubectl get pods -l app=alert-flood -n ${NAMESPACE} -w"
echo ""
echo " Observe Instana for:"
echo " 1) How does it aggregate these 200 failures?"
echo " 2) What severity/priority is assigned to the resulting incident?"
echo "======================================================================"
