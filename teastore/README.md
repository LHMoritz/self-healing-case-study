# TeaStore Kubernetes Deployment

This directory contains all necessary resources to deploy the TeaStore application on a Kubernetes cluster.

## About TeaStore

TeaStore is a microservice reference application developed by the University of Würzburg. It consists of multiple services:

- **teastore-db**: MySQL database for persistence
- **teastore-registry**: Service discovery and registry
- **teastore-persistence**: Data access layer
- **teastore-auth**: Authentication service
- **teastore-image**: Image management service
- **teastore-recommender**: Product recommendation service
- **teastore-webui**: Web frontend (accessible via NodePort 30080)

## Quick Start - One Command Installation

```bash
./deploy.sh
```

## Manual Installation

### Prerequisites

- A running Kubernetes cluster
- `kubectl` configured and connected to the cluster
- Sufficient cluster resources (approx. 4GB RAM, 2 CPU cores recommended)

### Deployment

```bash
kubectl apply -f teastore-clusterip.yaml
```

### Check Deployment Status

```bash
kubectl get pods -l app=teastore
kubectl get services -l app=teastore
```

Wait until all pods are in `Running` state:

```bash
kubectl wait --for=condition=ready pod -l app=teastore --timeout=300s
```

### Access the Application

The TeaStore WebUI is accessible via NodePort 30080:

```bash
# With Minikube:
minikube service teastore-webui --url

# With other clusters:
# http://<NODE-IP>:30080
```

Alternative access via port-forward:

```bash
kubectl port-forward service/teastore-webui 8080:8080
# Then accessible at: http://localhost:8080
```

## Uninstallation

```bash
kubectl delete -f teastore-clusterip.yaml
```

Or use the teardown script:

```bash
./teardown.sh
```

## Architecture

```
┌─────────────────┐
│  teastore-webui │ (NodePort 30080)
└────────┬────────┘
         │
    ┌────┴──────────────────┬──────────────┬────────────┐
    │                       │              │            │
┌───▼────────┐   ┌─────────▼──────┐   ┌──▼─────┐   ┌──▼──────────┐
│ teastore-  │   │  teastore-     │   │teastore│   │  teastore-  │
│   auth     │   │  persistence   │   │ image  │   │ recommender │
└───┬────────┘   └────────┬───────┘   └────────┘   └─────────────┘
    │                     │
    │            ┌────────▼────────┐
    └────────────►  teastore-db    │
                 │    (MySQL)      │
                 └─────────────────┘
                 
         ┌──────────────────┐
         │ teastore-registry│ (Service Discovery)
         └──────────────────┘
```

## Troubleshooting

### Pods not starting

```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### Services not reachable

```bash
kubectl get endpoints -l app=teastore
```

### Check resources

```bash
kubectl top pods -l app=teastore
kubectl top nodes
```

## Additional Information

- Original Repository: https://github.com/DescartesResearch/TeaStore
- Upstream YAML: https://raw.githubusercontent.com/DescartesResearch/TeaStore/master/examples/kubernetes/teastore-clusterip.yaml
