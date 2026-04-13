#!/bin/bash

# TeaStore Deployment Script
# Deploys the TeaStore application to the configured Kubernetes cluster

set -e

echo "🚀 Deploying TeaStore to Kubernetes..."
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed or not in PATH"
    exit 1
fi

# Check cluster connection
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ No connection to Kubernetes cluster"
    echo "Please ensure kubectl is configured correctly"
    exit 1
fi

echo "✅ Kubernetes cluster reachable"
CURRENT_CONTEXT=$(kubectl config current-context)
echo "📍 Current context: $CURRENT_CONTEXT"
echo ""

# Change to script directory
cd "$(dirname "$0")"

# Deploy TeaStore
echo "📦 Deploying TeaStore components..."
kubectl create namespace teastore --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f ../teastore/teastore-rabbitmq.yaml
kubectl apply -f ../teastore/teastore-ribbon-kieker.yaml

# Observability Namespace & OpenTelemetry
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f ../observability/opentelemetry/otel-collector-config.yaml
kubectl apply -f ../observability/opentelemetry/otel-collector-k8s.yaml

# Visualization (Prometheus, Loki, Grafana)
kubectl apply -f ../observability/visualization/loki.yaml
kubectl apply -f ../observability/visualization/prometheus.yaml
kubectl apply -f ../observability/visualization/grafana-config.yaml
kubectl apply -f ../observability/visualization/grafana.yaml

# Load Generation
kubectl apply -f ../load-generation/locust-k8s.yaml

echo ""
echo "⏳ Waiting for pods to be ready..."
echo ""

# Wait for all pods
kubectl wait --for=condition=ready pod -l app=teastore -n teastore --timeout=300s || {
    echo "⚠️  Timeout waiting for pods"
    echo "Current status:"
    kubectl get pods -l app=teastore -n teastore
    exit 1
}

echo ""
echo "✅ All TeaStore pods are ready!"
echo ""

# Show status
echo "📊 Deployment Status:"
echo "===================="
kubectl get pods -l app=teastore -n teastore
echo ""
kubectl get services -l app=teastore -n teastore
echo ""

# Show access information
echo "🌐 Access TeaStore WebUI:"
echo "=============================="

# Check if Minikube is being used
if command -v minikube &> /dev/null && [[ "$CURRENT_CONTEXT" == *"minikube"* ]]; then
    echo "Minikube detected. Getting service URL..."
    WEBUI_URL=$(minikube service teastore-webui --url 2>/dev/null)
    echo "URL: $WEBUI_URL"
else
    # Get first node IP
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' || \
              kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    echo "URL: http://$NODE_IP:30080"
fi

echo ""
echo "Alternative with port-forward:"
echo "  kubectl port-forward service/teastore-webui 8080:8080"
echo "  Then accessible at: http://localhost:8080"
echo ""

echo "✨ TeaStore successfully deployed!"
