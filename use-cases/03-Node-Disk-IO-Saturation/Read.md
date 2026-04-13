# Goal of the Node Disk IO Saturation Scenario  
## Infrastructure-Level Bottleneck Evaluation

## 1. Purpose of the Experiment

The purpose of this scenario is to simulate infrastructure-level disk IO saturation on a Kubernetes node in order to evaluate the AI-agent-based observability system’s ability to detect and contextualize cross-layer performance bottlenecks.

In cloud-native environments, node-level resource constraints may propagate across multiple workloads and lead to cascading service degradation.

---

## 2. Conceptual Objective

This experiment aims to assess whether the observability platform:

- Identifies abnormal IO patterns at the node level,
- Correlates infrastructure metrics with application-level symptoms,
- Performs dependency mapping across nodes, pods, and services,
- Distinguishes root causes from secondary effects.

The focus is on evaluating cross-layer reasoning rather than isolated metric threshold detection.

---

## 3. ITSM Perspective

From an ITSM perspective, this scenario primarily relates to:

- Incident Management,
- Problem Management.

The experiment explores whether AI-supported observability enhances root cause identification and supports structural problem resolution by revealing recurring infrastructure constraints.

---

## 4. Architecture and Pod Placement

```
                    ┌─────────────────────────────────────────────────┐
                    │              AKS Cluster (<YOUR_CLUSTER_NAME>)          │
                    │                                                 │
                    │   ┌─────────────────────────────────────────┐  │
                    │   │  Target Node (e.g. Node-1)              │  │
                    │   │                                         │  │
                    │   │  ┌──────────────┐  ┌─────────────────┐  │  │
                    │   │  │ teastore-*   │  │ io-stress       │  │  │
                    │   │  │ (app pods)   │  │ (DaemonSet Pod) │  │  │
                    │   │  │              │  │ Disk IO burn    │  │  │
                    │   │  └──────────────┘  └─────────────────┘  │  │
                    │   │                                         │  │
                    │   │  [ Shared Host OS Filesystem & Disk ]   │  │
                    │   └─────────────────────────────────────────┘  │
                    │                                                 │
                    │   ┌──────────────────┐                          │
                    │   │ Locust           │                          │
                    │   │ (load-generation)│                          │
                    │   └──────────────────┘                          │
                    └─────────────────────────────────────────────────┘
```

**Note on Pod Distribution:** The activation script dynamically locates the node currently hosting the `teastore-db` pod and deploys the IO stressor there. 
- If multiple application pods share this node (Single-Node Stack), the stressor causes simultaneous IO starvation for all of them ("Shared Infrastructure Bottleneck").
- If the database is relatively isolated (Multi-Node Stack), the stressor degrades the DB first, which then causes cascading network timeouts to dependent services like `teastore-persistence` ("Network Cascading Failure").

---

## 5. Experiment Execution

### Phase 1: Baseline
1.  Ensure Locust is running (e.g., 50 users, spawn rate 5) via the web UI to simulate continuous background traffic.
2.  Record baseline metrics in Instana (Node IO, Latency of `teastore-db`).

### Phase 2: Inject IO Stress
1.  Run `./activate.sh`. The script automatically locates the DB node and deploys a privileged DaemonSet (`node-io-stress`) to the target node.
2.  This pod runs `polinux/stress` in a shell loop via a `hostPath` mount to saturate the underlying node disk IO queues while handling Azure throttling gracefully.
3.  Locust test continues — user-facing response times should rise substantially.

### Phase 3: Observation
1.  Monitor Instana for an alert on **Node Disk IO**.
2.  Check if Instana correlates the poor application response times to this underlying infrastructure alert.
3.  Validate if the root cause analysis engine identifies the `io-stress` pod as the noisy neighbor.

### Phase 4: Recovery
1.  Run `./deactivate.sh`.
2.  The stress pod is deleted and the node label is removed.
3.  Verify IOPS return to baseline and Locust response times recover.

---

## 6. Scripts & Manifests

| File | Purpose |
|---|---|
| `activate.sh` | Finds DB node, labels it, applies stressor |
| `deactivate.sh` | Removes label, deletes stressor |
| `manifests/io-stress-daemonset.yaml` | DaemonSet restricting the `stress` pod to the labeled node |

---

## 7. Evaluation Criteria

| Criteria | Question |
|---|---|
| **Anomaly Detection** | Did Instana detect the disk IO saturation at the node level? |
| **Service Correlation** | Were slow application responses linked to the node-level issue? |
| **Topology Awareness** | Did Instana's topology graph correctly show the dependency slice affected by the failing node? |
| **Root Cause** | Was the `io-stress` pod correctly identified as the noisy neighbor culprit? |