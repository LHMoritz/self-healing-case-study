# Performance & Resource Utilization Scenario — Implementation Plan
## AKS + TeaStore + Stress Sidecar Injection

This document describes the step-by-step implementation of the performance degradation experiment. The approach uses a **stress sidecar container** injected into selected TeaStore pods to simulate sustained CPU and memory pressure. The existing Locust setup provides realistic user traffic to make the degradation observable. This enables evaluation of whether Instana detects resource anomalies, correlates them across services, and supports automated remediation.

**No application code changes are required.** Only deployment configurations are modified to inject a stress container and to set resource limits via YAML manifests.

---

## Prerequisites

- AKS cluster provisioned and accessible via `kubectl`
- Instana agent deployed and collecting data from the AKS cluster
- TeaStore application deployed and operational in namespace `teastore`
- Metrics Server available on the cluster (`kubectl top pods` works)
- Locust deployed via `load-generation/locust-k8s.yaml` (see [load-generation/README.md](../../load-generation/README.md))

---

## Architecture Overview

```
                    ┌─────────────────────────────────────────────────┐
                    │              AKS Cluster (<YOUR_CLUSTER_NAME>)          │
                    │                                                 │
                    │   ┌─────────────────────────────────────────┐  │
                    │   │  teastore-webui Pod                      │  │
                    │   │  ┌──────────────┐  ┌─────────────────┐  │  │
                    │   │  │ teastore-    │  │ stress          │  │  │
                    │   │  │ webui (app)  │  │ (sidecar)       │  │  │
                    │   │  │             │  │ CPU + Mem burn  │  │  │
                    │   │  └──────────────┘  └─────────────────┘  │  │
                    │   └─────────────────────────────────────────┘  │
                    │                                                 │
                    │   ┌─────────────────────────────────────────┐  │
                    │   │  teastore-persistence Pod                │  │
                    │   │  ┌──────────────┐  ┌─────────────────┐  │  │
                    │   │  │ teastore-    │  │ stress          │  │  │
                    │   │  │ persistence │  │ (sidecar)       │  │  │
                    │   │  │             │  │ CPU + Mem burn  │  │  │
                    │   │  └──────────────┘  └─────────────────┘  │  │
                    │   └─────────────────────────────────────────┘  │
                    │                                                 │
                    │   ┌──────────────────┐  ┌──────────────────┐  │
                    │   │ Locust           │  │ HPA (optional)   │  │
                    │   │ (load-generation)│  │ target: webui    │  │
                    │   │ 50 users, rate 5 │  │ CPU target: 50%  │  │
                    │   └──────────────────┘  └──────────────────┘  │
                    │                                                 │
                    │   teastore-db, teastore-registry,               │
                    │   teastore-auth, teastore-image,                │
                    │   teastore-recommender  (unchanged)             │
                    └─────────────────────────────────────────────────┘
```

**Stress mechanism:** A lightweight `polinux/stress` sidecar container is injected into targeted pods. It runs `stress --cpu N --vm M --vm-bytes B` to create sustained CPU and memory load, competing for the pod's shared cgroup resources.

---

## Approach: Stress Sidecar Injection

### Why a Sidecar?

- **No application code changes** — the stock TeaStore images are used as-is
- **Resource contention is realistic** — the sidecar shares the pod's cgroup budget, causing genuine CPU throttling and memory pressure
- **Easy to activate and deactivate** — scripted via `activate.sh` / `deactivate.sh`
- **Observable** — Instana and Kubernetes metrics show both the stress and application containers independently

### Target Pods

| Target | Rationale |
|---|---|
| `teastore-webui` | User-facing — latency increase directly observable via Locust response times |
| `teastore-persistence` | Data layer — stress here affects all dependent services through slow DB queries |

---

## Step 1: Create Resource Limits Manifest

Currently, pods only have resource **requests** (256Mi memory, 100m CPU) but no **limits**. Resource limits are required so CPU throttling and OOMKill events become observable.

### [NEW] `manifests/resource-limits.yaml`

```yaml
# This file is applied by activate.sh and contains the resource limits
# for the target deployments. It is applied as a strategic merge patch.
```

The `activate.sh` script will apply these limits as a JSON patch to add `resources.limits` to the target containers. The exact limits will be defined in the activate script to keep the manifests directory focused on standalone K8s resources.

> **Note:** If preferred, a full copy of the modified deployments can be stored in `manifests/` as reference YAML, similar to `teastore-ribbon-kieker-modified.yaml` in UC01.

---

## Step 2: Create HPA Manifest (Optional)

### [NEW] `manifests/hpa-webui.yaml`

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: teastore-webui-hpa
  namespace: teastore
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: teastore-webui
  minReplicas: 1
  maxReplicas: 3
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
```

---

## Step 3: Create `activate.sh`

The activate script performs the following steps in order:

1. **Deploy Locust** — `kubectl apply -f` the existing `load-generation/locust-k8s.yaml` (in the correct namespace)
2. **Set resource limits** — patch `teastore-webui` and `teastore-persistence` to add CPU/memory limits using a YAML patch file from `manifests/`
3. **Inject stress sidecar** — patch both deployments to add the `stress` sidecar container
4. **Deploy HPA** (optional, via flag) — apply `manifests/hpa-webui.yaml`
5. **Wait for rollout** — `kubectl rollout status` for both deployments
6. **Print instructions** — how to access Locust UI, how to start load, and how to observe in Instana

### Script Skeleton

```bash
#!/bin/bash
set -euo pipefail
NAMESPACE="${1:-teastore}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Step 1: Deploy Locust
kubectl apply -f "${REPO_ROOT}/load-generation/locust-k8s.yaml" -n "${NAMESPACE}"

# Step 2: Apply resource limits from YAML patches
kubectl apply -f "${SCRIPT_DIR}/manifests/resource-limits.yaml" -n "${NAMESPACE}"

# Step 3: Inject stress sidecar into webui and persistence
# (kubectl patch with JSON patch to add sidecar container)

# Step 4: Wait for rollout
kubectl rollout status deployment/teastore-webui -n "${NAMESPACE}" --timeout=120s
kubectl rollout status deployment/teastore-persistence -n "${NAMESPACE}" --timeout=120s

# Step 5: Print status and instructions
```

> The script will follow the same patterns as `01-secret-experation/activate.sh`: usage header, colored output, namespace parameter, error handling.

---

## Step 4: Create `deactivate.sh`

The deactivate script reverses all changes:

1. **Remove stress sidecar** — patch both deployments to remove the sidecar container
2. **Remove resource limits** — patch both deployments to remove the `limits` key
3. **Remove HPA** — `kubectl delete hpa` (if it exists)
4. **Remove Locust** — `kubectl delete -f load-generation/locust-k8s.yaml`
5. **Wait for rollout** — confirm pods return to normal
6. **Verify** — print pod status and resource usage

---

## Step 5: Expand `Read.md`

Expand the existing `Read.md` with full documentation following the UC01 schema:

- Architecture diagram (with Locust and stress containers)
- Components table
- What was modified (sidecar injection, resource limits)
- Experiment phases (baseline → stress → observe → recover)
- Scripts table
- Manifests table
- Evaluation criteria
- ITSM process mapping
- Technical details (stress parameters, Locust configuration)

---

## Experiment Execution Sequence

### Phase 0: Baseline (5–10 min)

1. Run `activate.sh` (without stress injection initially — just Locust + limits)
2. Start Locust via web UI (port 30089): 50 users, spawn rate 5
3. Record baseline metrics in Instana and via `kubectl top pods -n teastore`

### Phase 1: Inject Stress (10–15 min)

1. Stress sidecars are injected via `activate.sh`
2. Locust continues generating load — response times should increase
3. Observe Instana for anomaly detection, alerts, service topology changes
4. Monitor `kubectl top pods -n teastore` for resource consumption

### Phase 2: Escalation (Optional, 5 min)

1. Increase stress intensity (more CPU workers, higher memory)
2. Observe whether Instana detects the escalation and adjusts alerts

### Phase 3: Recovery

1. Run `deactivate.sh`
2. Confirm pods return to normal resource usage
3. Document how quickly Instana reflects the recovery

---

## Evaluation Criteria

| Criteria | Question |
|---|---|
| **Anomaly Detection** | Did Instana detect sustained CPU/memory anomalies? How quickly? |
| **Alert Quality** | Did Instana distinguish sustained degradation from transient spikes? |
| **Service Correlation** | Were performance impacts correlated across `webui` → `persistence` → `db`? |
| **Topology Awareness** | Did Instana highlight bottleneck services in the topology view? |
| **Root Cause** | Did Instana identify the specific pods/containers with resource contention? |
| **Remediation** | Did Instana suggest scaling, restart, or other remediation? |

### ITSM Process Mapping

| ITSM Practice | Relevance |
|---|---|
| **Monitoring & Event Management** | Detection of sustained resource anomalies and threshold breaches |
| **Incident Management** | Alert creation, prioritization, and correlation into incidents |
| **Capacity Management** | Detection of resource exhaustion and scaling recommendations |

---

## Deliverables (Files to Create)

| File | Purpose | Status |
|---|---|---|
| `Plan.md` | This document — implementation plan | ✓ exists |
| `Read.md` | Full documentation — **to be expanded** | ✓ exists (stub) |
| `activate.sh` | Deploys Locust, sets resource limits, injects stress sidecars | **NEW** |
| `deactivate.sh` | Removes stress sidecars, limits, and Locust | **NEW** |
| `manifests/stress-patch-webui.yaml` | Strategic merge patch for webui (limits + sidecar) | **NEW** |
| `manifests/stress-patch-persistence.yaml` | Strategic merge patch for persistence (limits + sidecar) | **NEW** |

---

## Verification Plan

### Automated Checks (inside `activate.sh`)
- `kubectl rollout status` confirms pods start successfully with sidecar
- `kubectl get pods` confirms 2 containers per target pod
- `kubectl top pods` confirms elevated resource usage

### Manual Verification
1. Access Locust UI via `kubectl port-forward svc/locust 8089:8089` or NodePort 30089
2. Start a test (50 users, spawn rate 5) and observe response times increase
3. Check Instana dashboards for anomaly alerts on `teastore-webui` and `teastore-persistence`
4. Run `deactivate.sh` and confirm all resources are cleaned up and metrics return to normal
