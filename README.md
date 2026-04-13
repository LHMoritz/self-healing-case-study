# Self-Healing Case Study

A research case study evaluating the self-healing potential of incident management tools in a Kubernetes environment. The setup uses the [TeaStore](https://github.com/DescartesResearch/TeaStore) microservice benchmark application running on AKS, monitored via [Instana](https://www.instana.com/).

## Overview

Three failure scenarios are implemented and evaluated completely. Two more are prepared but have not been evaluated. Each use case deliberately triggers a specific infrastructure or application failure and observes whether the monitoring tool can detect and automatically remediate it.

## Repository Structure

```
.
├── teastore/               # TeaStore K8s deployment manifests
├── load-generation/        # Locust-based load generator (K8s + script)
├── instana-installation/   # Instana agent deployment (Helm/operator)
├── observability/          # OpenTelemetry collector, Prometheus, Grafana, Loki
├── scripts/                # deploy.sh / teardown.sh and verification helpers
└── use-cases/              # One folder per failure scenario
    ├── 01-secret-experation/
    ├── 02-Performance-Alerts/
    ├── 03-Node-Disk-IO-Saturation/
    ├── 04-Persistent-Volume-Claim-Storage-Exhaustion/
    └── 05-High-Volume-Alert-Scenario/
```

Each use case folder contains:
- `Plan.md` — design, architecture diagram, and goals
- `Read.md` — implementation notes and observations
- `activate.sh` — triggers the failure scenario
- `deactivate.sh` — restores the system to a healthy state
- `manifests/` — Kubernetes manifests specific to the scenario

## Use Cases

| # | Scenario | Failure Type |
|---|----------|-------------|
| 01 | Secret Expiration | Azure Key Vault secret expires → DB connection fails |
| 02 | Performance Alerts | CPU/memory stress on pods → latency spike detected |
| 03 | Node Disk I/O Saturation | DaemonSet saturates node disk I/O |
| 04 | PVC Storage Exhaustion | Sidecar fills a persistent volume to capacity |
| 05 | High-Volume Alert Scenario | Flood of alerts to test alert correlation |

## Prerequisites

- AKS cluster with Secrets Store CSI Driver and Workload Identity enabled — use [Cloud-agnostic-managed-k8s-cluster](https://github.com/LHMoritz/Cloud-agnostic-managed-k8s-cluster) to provision one
- Azure CLI (`az`) authenticated
- `kubectl` configured against the cluster
- Instana agent deployed (see `instana-installation/`)
- Helm 3

## Quick Start

```bash
# Deploy TeaStore
./scripts/deploy.sh

# Run a use case (example: use case 01)
cd use-cases/01-secret-experation
./activate.sh            # trigger the failure
./deactivate.sh          # restore

# Tear down everything
./scripts/teardown.sh
```

## Configuration

Scripts expect the following variables to be set (either hardcoded in the script or via environment):

| Variable | Description |
|----------|-------------|
| `RESOURCE_GROUP` | Azure Resource Group containing the AKS cluster |
| `AKS_CLUSTER_NAME` | Name of the AKS cluster |
| `KEYVAULT_NAME` | Azure Key Vault name (used in use case 01) |

Placeholders like `<YOUR_RESOURCE_GROUP>` are used throughout — replace them with your own values before running.

## Observability Stack

| Tool | Purpose |
|------|---------|
| Instana | Primary incident detection and self-healing evaluation |
| OpenTelemetry | Trace collection from TeaStore via Kieker |
| Prometheus | Metric scraping |
| Grafana + Loki | Dashboards and log aggregation |
