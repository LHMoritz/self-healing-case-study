#!/bin/bash

# TeaStore Teardown Script
# Removes all TeaStore resources from the Kubernetes cluster

set -e

echo "🧹 Removing TeaStore from Kubernetes..."
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed or not in PATH"
    exit 1
fi

# Change to script directory
cd "$(dirname "$0")"

# Show current resources
echo "📊 Current TeaStore resources:"
kubectl get all -l app=teastore 2>/dev/null || echo "No resources found"
echo ""

# Delete TeaStore
echo "🗑️  Deleting TeaStore components..."
kubectl delete namespace observability --ignore-not-found=true
kubectl delete -f ../teastore/teastore-ribbon-kieker.yaml --ignore-not-found=true
kubectl delete -f ../teastore/teastore-rabbitmq.yaml --ignore-not-found=true
kubectl delete -f ../load-generation/locust-k8s.yaml --ignore-not-found=true
kubectl delete -f ../observability/opentelemetry/otel-collector-k8s.yaml --ignore-not-found=true
kubectl delete -f ../observability/opentelemetry/otel-collector-config.yaml --ignore-not-found=true
kubectl delete -f ../observability/visualization/loki.yaml --ignore-not-found=true
kubectl delete -f ../observability/visualization/grafana.yaml --ignore-not-found=true
kubectl delete -f ../observability/visualization/grafana-config.yaml --ignore-not-found=true
kubectl delete -f ../observability/visualization/prometheus.yaml --ignore-not-found=true

echo ""
echo "⏳ Waiting for complete removal..."
sleep 5

# Check if pods still exist
REMAINING_PODS=$(kubectl get pods -l app=teastore --no-headers 2>/dev/null | wc -l)
if [ "$REMAINING_PODS" -gt 0 ]; then
    echo "⚠️  Still $REMAINING_PODS pod(s) terminating..."
    kubectl get pods -l app=teastore
else
    echo "✅ All pods successfully removed"
fi

echo ""
echo "✨ TeaStore teardown completed!"
