# Use Case 02 — Performance & Resource Utilization
## AKS + TeaStore + Stress Sidecar Injection

---

## 1. Purpose

This experiment evaluates whether Instana, as an AI-agent-based observability platform, can:

1. **Detect sustained resource anomalies** (elevated CPU and memory usage) rather than transient fluctuations.
2. **Correlate alerts** across services, pods, and infrastructure layers within a distributed microservice topology.
3. **Identify performance bottlenecks** and pinpoint the affected containers/pods.
4. **Support or enable automated remediation** such as scaling or workload restart.

The experiment reflects common operational challenges in cloud-native DevOps environments, where high CPU usage, memory saturation, or storage pressure may lead to increased latency, pod instability, or degraded service quality.

The focus is not on performance benchmarking but on evaluating the system's reasoning, contextualization, and automation capabilities.

---

## 2. Architecture

### 2.1 High-Level Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                    AKS Cluster (<YOUR_CLUSTER_NAME>)                        │
│                                                                     │
│   ┌──────────────────────────────────────────────────────────────┐  │
│   │  teastore-webui Pod                                          │  │
│   │  ┌─────────────────────────┐  ┌───────────────────────────┐ │  │
│   │  │ teastore-webui (app)    │  │ stress (sidecar)          │ │  │
│   │  │ image: stock TeaStore   │  │ image: polinux/stress     │ │  │
│   │  │ limits: 500m / 512Mi    │  │ stress --cpu 1 --vm 1     │ │  │
│   │  │                         │  │ --vm-bytes 200M           │ │  │
│   │  └─────────────────────────┘  └───────────────────────────┘ │  │
│   └──────────────────────────────────────────────────────────────┘  │
│                          │                                          │
│   ┌──────────────────────────────────────────────────────────────┐  │
│   │  teastore-persistence Pod                                    │  │
│   │  ┌─────────────────────────┐  ┌───────────────────────────┐ │  │
│   │  │ teastore-persistence    │  │ stress (sidecar)          │ │  │
│   │  │ image: stock TeaStore   │  │ image: polinux/stress     │ │  │
│   │  │ limits: 500m / 512Mi    │  │ stress --cpu 1 --vm 1     │ │  │
│   │  │                         │  │ --vm-bytes 200M           │ │  │
│   │  └─────────────────────────┘  └───────────────────────────┘ │  │
│   └──────────────────────────────────────────────────────────────┘  │
│                          │                                          │
│          ┌───────────────┼───────────────┐                          │
│          ▼               ▼               ▼                          │
│   teastore-db    teastore-auth    teastore-image                    │
│                  teastore-recommender                               │
│                  teastore-registry                                  │
│                  (all unchanged)                                    │
│                                                                     │
│   ┌──────────────────────┐                                        │
│   │ Locust               │                                        │
│   │ (teastore namespace) │                                        │
│   │ 50 users, rate 5     │                                        │
│   │ port: 30089          │                                        │
│   └──────────────────────┘                                        │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 Components

| Component | Role |
|---|---|
| **Stress sidecar** (`polinux/stress`) | Runs in target pods to create sustained CPU and memory pressure |
| **Resource limits** | Applied to app containers (500m CPU, 512Mi memory) so throttling and OOMKill are observable |
| **Locust** (`load-generation/`) | Deployed in `teastore` namespace; generates realistic user traffic (browse, login, buy) to surface latency degradation |
| **teastore-webui** | User-facing service — latency increase directly measurable via Locust |
| **teastore-persistence** | Data layer — stress affects all dependent services through slow DB queries |
| **All other TeaStore services** | Unmodified — affected indirectly through dependency on `persistence` |

---

## 3. What Was Modified

**Only `teastore-webui` and `teastore-persistence` deployments are modified.** All other TeaStore services remain unchanged. The modification consists of two changes per deployment:

1. **Resource limits added** — `cpu: 500m`, `memory: 512Mi` on the app container, making CPU throttling and memory pressure events observable
2. **Stress sidecar injected** — a `polinux/stress` container that runs `stress --cpu 1 --vm 1 --vm-bytes 200M` continuously, competing for the pod's cgroup resources

No application code is changed. The stock TeaStore images are used as-is.

---

## 4. Experiment Scenario

### Phase 0: Baseline (5–10 min)

1. Deploy Locust and start load generation (50 users, spawn rate 5)
2. Record baseline metrics in Instana and via `kubectl top pods`
3. Document healthy response times, error rates, and resource usage

### Phase 1: Inject Stress (10–15 min)

Run `./activate.sh` to inject stress sidecars and set resource limits.

**Expected Effects:**

```
Stress sidecar (CPU + memory burn)
        │
        ▼
teastore-webui: CPU throttled → response time ↑
teastore-persistence: CPU throttled → DB queries slow
        │
        ▼
All dependent services (auth, image, recommender):
  Calls to persistence slow → cascading latency increase
        │
        ▼
User-facing impact: TeaStore becomes sluggish
Locust metrics: response times increase, potential timeouts
```

**Evaluation:** How quickly does Instana detect the resource anomalies? Does it correlate performance degradation across affected services?

### Phase 2: Escalation (Optional, 5 min)

Increase stress intensity by modifying the sidecar args (more CPU workers, higher memory) to trigger more severe symptoms, potentially OOMKill events.

### Phase 3: Recovery

Run `./deactivate.sh` to remove stress sidecars, limits, HPA, and Locust.

---

## 5. Scripts

| Script | Purpose |
|---|---|
| `activate.sh` | Deploys Locust (in `teastore` namespace), sets resource limits via YAML patches, injects stress sidecars into `teastore-webui` and `teastore-persistence`. |
| `deactivate.sh` | Removes stress sidecars, resource limits, and Locust. Restores original deployment configurations. |

Both scripts accept an optional namespace argument (`./activate.sh [namespace]`, defaults to `teastore`).

---

## 6. Manifests

| File | Content |
|---|---|
| `manifests/stress-patch-webui.yaml` | Strategic merge patch: resource limits + stress sidecar for `teastore-webui` |
| `manifests/stress-patch-persistence.yaml` | Strategic merge patch: resource limits + stress sidecar for `teastore-persistence` |

---

## 7. Evaluation Criteria

| Criteria | Question |
|---|---|
| **Anomaly Detection** | Did Instana detect sustained CPU/memory anomalies? How quickly? |
| **Alert Quality** | Did Instana distinguish sustained degradation from transient spikes? |
| **Service Correlation** | Were performance impacts correlated across `webui` → `persistence` → `db`? |
| **Topology Awareness** | Did Instana highlight bottleneck services in the service topology view? |
| **Root Cause** | Did Instana identify the specific pods/containers with resource contention? |
| **Remediation** | Did Instana suggest scaling, restart, or other remediation? |

### ITSM Process Mapping

| ITSM Practice | Relevance |
|---|---|
| **Monitoring & Event Management** | Detection of sustained resource anomalies and threshold breaches |
| **Incident Management** | Alert creation, prioritization, and correlation into incidents |
| **Capacity Management** | Detection of resource exhaustion and scaling recommendations |

---

## 8. Key Technical Details

### Stress Sidecar Configuration

| Parameter | Value | Effect |
|---|---|---|
| `--cpu 1` | 1 CPU worker | Sustained CPU load, competes with app container for CPU time |
| `--vm 1` | 1 memory worker | Allocates and touches memory pages continuously |
| `--vm-bytes 200M` | 200MB allocation | Combined with app container (~256Mi request), pushes toward pod limits |
| `--timeout 0` | Runs indefinitely | Simulates sustained degradation, not a transient spike |

### Resource Limits

The original deployments have only resource **requests** (256Mi memory, 100m CPU). The experiment adds **limits** (512Mi memory, 500m CPU) so that:
- **CPU:** Exceeding the limit causes CPU throttling (visible in Instana as increased latency)
- **Memory:** Exceeding the limit triggers OOMKill events (visible in Instana as pod restarts)

### Locust Load Generation

The existing Locust setup (`load-generation/`) simulates realistic user behavior:
- Login, browse categories, view products, add to cart, purchase, logout
- 50 concurrent users with spawn rate of 5/sec
- Targets `http://teastore-webui:8080` via internal cluster DNS
- Accessible via NodePort 30089 or port-forward to 8089
