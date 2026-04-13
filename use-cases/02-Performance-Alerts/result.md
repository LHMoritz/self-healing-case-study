# Use Case 02 — Performance Alerts: Experiment Results

**Date:** 2026-02-22  
**Cluster:** <YOUR_CLUSTER_NAME> (AKS, 2× Standard_D4s_v3)  
**Namespace:** teastore

---

## 1. Experiment Configuration

### Stress Sidecar (CPU-only)

| Parameter | Value |
|---|---|
| Image | `polinux/stress` |
| Args | `--cpu 2 --timeout 99999999` |
| Sidecar CPU request/limit | 100m / 400m |
| Sidecar memory request/limit | 32Mi / 64Mi |
| App container CPU limit | 500m |
| App container memory limit | 1500Mi |

**Target deployments:** `teastore-webui`, `teastore-persistence`

### Locust Load Generation

| Parameter | Value |
|---|---|
| Concurrent users | 20 |
| Ramp-up rate | 2 users/sec |
| Target | `http://teastore-webui:8080` |
| User behavior | Browse, login, add to cart, buy, logout |

---

## 2. Observed Behavior

### Baseline (Experiment deactivated)

- Response times are within normal range
- Minimal error rate
- CPU usage of webui and persistence at normal levels (~12–80m CPU)
- Services communicate via the TeaStore registry without timeouts

### With Stress Activated

| Metric | Baseline | With Stress |
|---|---|---|
| `teastore-webui` CPU | ~82m | ~161m (stress sidecar: +401m) |
| `teastore-persistence` CPU | ~47m | ~150m (stress sidecar: +401m) |
| Total pod CPU (app + sidecar) | ~82m | ~560m (exceeds 500m limit → throttling) |
| Response times | Normal | Significantly elevated |
| Error rate | Low | Increased (timeouts due to CPU throttling) |

**Key observation:** The stress sidecar consumes ~401m of the 500m CPU limit, leaving the app container with only ~100m effective CPU. This causes CPU throttling, which manifests as:
- Increased response times across all endpoints
- Timeout errors in inter-service communication (webui → image, webui → persistence)
- Cascading latency through the service dependency chain

### Resource Usage Comparison

```
Without Stress:
  teastore-webui:         82m CPU,   1147Mi memory
  teastore-persistence:   47m CPU,    948Mi memory

With Stress:
  teastore-webui:        161m CPU,    926Mi memory  + stress: 401m CPU
  teastore-persistence:  150m CPU,    904Mi memory  + stress: 401m CPU
  → Combined:           ~560m CPU per pod (limit: 500m → throttled)
```

---

## 3. Issues Encountered During Setup

| Issue | Root Cause | Resolution |
|---|---|---|
| Pods OOMKilled (exit 137) | Memory limit 512Mi too low; Java apps need 600–1250Mi | Increased to 1500Mi |
| Stress sidecar exits immediately | `polinux/stress` rejects `--timeout 0` | Changed to `--timeout 99999999` |
| Memory stress crashes pods | `--vm-bytes 200M` combined with app memory exceeds limits | Switched to CPU-only stress (`--cpu 2`, no `--vm`) |
| High response times after deactivation | Registry held stale pod IPs from repeated restarts | Rolled all deployments to re-register cleanly |

---

## 4. Signals for Instana

The experiment produces the following observable signals that Instana should detect:

1. **CPU throttling** — Pod CPU usage at or exceeding limits, causing kernel-level throttling
2. **Increased service latency** — Measurable via Locust and correlated in Instana traces
3. **Timeout errors** — Inter-service calls (webui → image, webui → persistence) exceeding timeouts
4. **Cascading degradation** — Performance impact flows through the service topology:
   `webui → persistence → db` and `webui → image`
5. **Resource anomalies** — CPU utilization significantly above normal baseline

### Expected Instana Capabilities

| Capability | Expected Behavior |
|---|---|
| Anomaly detection | Detect sustained CPU utilization spike on webui and persistence |
| Alert correlation | Correlate performance degradation across dependent services |
| Topology awareness | Highlight bottleneck services in the service map |
| Root cause analysis | Identify the specific pods/containers with resource contention |
| Remediation suggestion | Propose scaling (HPA) or resource limit adjustment |

---

## 5. Scripts

| Action | Command |
|---|---|
| Activate experiment | `./activate.sh [namespace]` |
| Deactivate experiment | `./deactivate.sh [namespace]` |
| Deploy full stack (incl. Locust) | `sh scripts/deploy.sh` |
| Teardown full stack (incl. Locust) | `sh scripts/teardown.sh` |
