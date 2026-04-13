#!/bin/bash

# Find the OpenTelemetry Collector Pod
POD=$(kubectl get pod -l app=opentelemetry -o jsonpath="{.items[0].metadata.name}")

if [ -z "$POD" ]; then
    echo "❌ No OpenTelemetry Collector pod found!"
    exit 1
fi

echo "🔍 Found Collector Pod: $POD"
echo "🚀 Setting up temporary port-forward to port 8889..."

# Start port-forward in background
kubectl port-forward $POD 8889:8889 > /dev/null 2>&1 &
PF_PID=$!

# Wait for connection to be ready
sleep 2

echo "📊 Fetching Metrics (first 50 lines)..."
echo "========================================"
curl -s http://localhost:8889/metrics | head -n 50
echo "..."
echo "========================================"

# Cleanup
echo "🧹 Cleaning up..."
kill $PF_PID
