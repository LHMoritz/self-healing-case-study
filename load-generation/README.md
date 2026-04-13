# Load Generation (Locust)

This directory contains the setup for running load tests against the TeaStore using **Locust**.

## Files
- **`locustfile.py`**: The traffic simulation script (Python).
- **`locust-k8s.yaml`**: Kubernetes resources (ConfigMap, Deployment, Service).

## 🚀 Quick Start

### 1. Deploy Locust
```bash
kubectl apply -f locust-k8s.yaml
```

### 2. Access the Web UI
The service is exposed via NodePort **30089**.

**If using Minikube / Docker Desktop:**
You can likely access it at: `http://localhost:30089`

**If that doesn't work, use port-forwarding:**
```bash
kubectl port-forward svc/locust 8089:8089
```
Then open: [http://localhost:8089](http://localhost:8089)

### 3. Start a Test
1. Open the UI.
2. Enter number of users (e.g., **50**) and spawn rate (e.g., **5**).
3. The "Host" field should already be populated with `http://teastore-webui:8080` (internal cluster DNS). If not, verify that value.
4. Click **Start Swarming**.

## 🛑 Cleanup
```bash
kubectl delete -f locust-k8s.yaml
```
