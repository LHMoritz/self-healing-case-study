# Observability Access Guide

This directory contains the configuration for the OpenTelemetry Collector, which gathers logs and metrics from the TeaStore application.

## 1. 🪵 Logs (OpenTelemetry)

Logs are collected by the OpenTelemetry Collector and persisted to the host machine.

### Location
- **Host Path**: `/tmp/teastore-logs/teastore.json`
- **Container Path**: `/logs/teastore.json` (inside Log Viewer)

### How to View Logs
**Using the Log Viewer (Recommended):**
```bash
kubectl exec log-viewer -- tail -f /logs/teastore.json
```

**Direct on Node:**
```bash
tail -f /tmp/teastore-logs/teastore.json
```

---

## 2. 📊 Metrics (OpenTelemetry & Prometheus)

The OpenTelemetry Collector scrapes metrics from the Kubernetes Host and Kubelet and exposes them in **Prometheus format**.

### Accessing Metrics
The collector exposes a `/metrics` endpoint on port **8889**.

**1. Forward the Port:**
```bash
# Get the pod name
POD=$(kubectl get pod -l app=opentelemetry -o jsonpath="{.items[0].metadata.name}")

# Forward port 8889
kubectl port-forward $POD 8889:8889
```

**2. View Metrics:**
Open your browser to [http://localhost:8889/metrics](http://localhost:8889/metrics) or use curl:
```bash
curl http://localhost:8889/metrics
```

**3. Integration:**
You can configure a Prometheus server to scrape this endpoint by adding a scrape job for the `otel-collector` pod on port `8889`.

---

## 3. 🔍 Traces (Kieker)

**Note:** Distributed tracing is handled by **Kieker** via RabbitMQ.

### Accessing Traces
**Via Web UI:**
`http://localhost:30081/logs/` (requires port-forwarding `svc/teastore-kieker-rabbitmq` 30081:8080)

**Via Script:**
```bash
cd ../../scripts
sh test_kieker.sh localhost 30081
```
