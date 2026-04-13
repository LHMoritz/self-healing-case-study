# Node Disk IO Saturation Scenario — Implementation Plan
## AKS + TeaStore + IO Stressor

This document describes the step-by-step implementation of the Node Disk IO saturation experiment. The approach uses a **privileged IO stressor pod** (e.g., using `fio` or `stress-ng`) deployed to a specific Kubernetes node to simulate sustained infrastructure-level disk IO exhaustion. By targeting the node that hosts IO-sensitive workloads like the TeaStore database (`teastore-db`) or image service (`teastore-image`), we can observe how the bottleneck propagates across services. 

This scenario evaluates whether Instana can detect the node-level constraint, map the dependencies from the node up to the pods and services, and correctly identify the infrastructure saturation as the root cause of the resulting application performance degradation.

**No application code changes are required.** The simulation relies entirely on adding load at the infrastructure layer using a targeted DaemonSet or Pod.

---

## Prerequisites

- AKS cluster provisioned and accessible via `kubectl`
- Instana agent deployed and collecting data from the AKS cluster
- TeaStore application deployed and operational in namespace `teastore`
- Locust deployed via `load-generation/locust-k8s.yaml` (to provide an observable baseline user traffic)

---

## Architecture Overview

```
                    ┌─────────────────────────────────────────────────┐
                    │              AKS Cluster (<YOUR_CLUSTER_NAME>)          │
                    │                                                 │
                    │   ┌─────────────────────────────────────────┐  │
                    │   │  Node-A (Target Node)                   │  │
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

**Stress mechanism:** A container running `fio` or `stress-ng` mounts a `hostPath` volume (or simply reads/writes heavily to the container's ephemeral storage, depending on class) to consume read/write IOPS and saturate the disk queue. This starves other pods on the same node of IO capacity. 

*Note on Pod Placement:* If all TeaStore pods run on a single node, the stressor acts as a massive failure domain and causes IO wait for all app components (`webui`, `persistence`, `db`) simultaneously. If pods are distributed across multiple nodes, only the pods on the stressed node (e.g., `teastore-db`) will degrade initially, creating a classic "cascading failure" over the network. Both scenarios are valid tests for the observability platform, but a single-node setup tests correlation of a shared infrastructure bottleneck across multiple parallel services.

---

## Approach: Node-Targeted IO Stress

### Why targeted IO stress?

- **Realism** — Disk contention is a common "noisy neighbor" problem in multi-tenant clusters.
- **Cross-Layer Topology** — It forces the observability tool to connect an infrastructure metric (Node Disk IO) to a pod performance issue (slow DB queries), and finally to a service degradation (slow web UI responses).
- **Safe Activation** — By labeling a specific node (e.g., the one running `teastore-db`) and restricting our stressor to that label, we precisely control the blast radius.

---

## Step 1: Create IO Stressor Manifest

### [NEW] `manifests/io-stress-daemonset.yaml`

We will create a DaemonSet that uses a `nodeSelector` or `nodeAffinity` to only schedule on nodes with a specific label, such as `teastore-experiment-io-stress=true`. 

The pod will run a workload capable of generating massive IO operations using the `polinux/stress` image, writing to a mounted `hostPath` to ensure it hits the node's underlying disk directly. 

**Note on Stability:** Due to Azure's I/O burst throttling, continuous high-performance writes can cause the `stress` tool to exit with Error 1 (I/O error). We wrap the command in a `while true` shell loop within the manifest to ensure the stressor remains active throughout the experiment without entering a `CrashLoopBackOff`.

```yaml
# Actual snippet for io-stress-daemonset.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-io-stress
  namespace: teastore
spec:
  selector:
    matchLabels:
      app: io-stress
  template:
    metadata:
      labels:
        app: io-stress
    spec:
      nodeSelector:
        teastore-experiment-io-stress: "true"
      containers:
      - name: stress
        image: polinux/stress
        workingDir: /stress-data
        command: ["/bin/sh", "-c"]
        args: ["while true; do stress --hdd 2 --hdd-bytes 1G --io 4 --timeout 60s || true; sleep 1; done"]
        volumeMounts:
        - name: host-fs
          mountPath: /stress-data
      volumes:
      - name: host-fs
        hostPath:
          path: /tmp/stress-data
          type: DirectoryOrCreate
```

---

## Step 2: Create `activate.sh`

The activation script automates the process of finding the right node to stress and applying the stressor.

1. **Deploy Locust** — Ensure background traffic is running.
2. **Identify Target Node** — Use `kubectl` to find the node hosting the `teastore-db` or `teastore-persistence` pod.
3. **Label Node** — Label the identified node with `teastore-experiment-io-stress=true`.
4. **Deploy Stressor** — Apply the `io-stress-daemonset.yaml`.
5. **Print Status** — Confirm that the stress pod is spinning up on the target node.

### Script Skeleton

```bash
#!/bin/bash
set -euo pipefail
NAMESPACE="${1:-teastore}"

# 1. Deploy Locust...
# 2. Find Node running teastore-db
TARGET_NODE=$(kubectl get pod -l run=teastore-db -n "${NAMESPACE}" -o jsonpath='{.items[0].spec.nodeName}')

echo "▸ Found teastore-db running on node: ${TARGET_NODE}"

# 3. Label Node
kubectl label node "${TARGET_NODE}" teastore-experiment-io-stress=true --overwrite

# 4. Deploy IO Stressor
kubectl apply -f manifests/io-stress-daemonset.yaml -n "${NAMESPACE}"

# 5. Wait & Print instructions
```

---

## Step 3: Create `deactivate.sh`

The deactivation script cleans up the experiment, returning the system to normal operations.

1. **Delete DaemonSet** — `kubectl delete -f manifests/io-stress-daemonset.yaml`.
2. **Remove Node Label** — `kubectl label node "${TARGET_NODE}" teastore-experiment-io-stress-` to cleanly remove the label.
3. **Remove Locust** — (Optional, depending on cleanup strategy).
4. **Wait & Verify** — Ensure the stress pods are gone and IO usage normalizes.

---

## Step 4: Expand `Read.md`

Expand the existing `Read.md` with:
- Architecture diagram and note on pod distribution (single node vs. multi node impact).
- Step-by-step description of the experiment phases.
- Documentation of scripts and manifests used.
- Expected failure description depending on placement (Direct simultaneous IO starvation for all pods vs. network cascade).

---

## Experiment Execution Sequence

### Phase 0: Baseline
1. Start Locust (50 users, spawn rate 5) via web UI.
2. Record baseline metrics in Instana (Node IO, Latency of `teastore-db`, Latency of `teastore-webui`).

### Phase 1: Inject IO Stress
1. Run `./activate.sh`.
2. The stress pod starts on the node hosting the database.
3. Locust test continues — user-facing response times should rise substantially as DB queries queue up at the disk level.

### Phase 2: Observation (10-15 min)
1. Monitor Instana for alerts on Node Disk IO.
2. Check if Instana correlates the poor application response times to the infrastructure alert.
3. Validate if the root cause analysis engine points to the specific node and the noisy neighbor pod (`node-io-stress`).

### Phase 3: Recovery
1. Run `./deactivate.sh`.
2. Verify IOPS return to baseline and Locust response times recover.
3. Document how quickly Instana automatically closes the incident.

---

## Evaluation Criteria

| Criteria | Question |
|---|---|
| **Anomaly Detection** | Did Instana detect the disk IO saturation at the node level? |
| **Alert Quality** | Was an actionable alert generated reflecting an infrastructure bottleneck? |
| **Service Correlation** | Were slow application responses (e.g. in `webui` and `persistence`) linked to the node-level issue? |
| **Topology Awareness** | Did Instana's topology graph correctly show the dependency slice affected by the failing node? |
| **Root Cause** | Was the `io-stress` pod (the noisy neighbor) correctly identified as the culprit consuming the IO? |
| **ITSM: Problem Mgmt** | Would this information be sufficient to construct a problem record for recurring noisy neighbor issues? |

---

## Deliverables (Files to Create)

| File | Purpose | Status |
|---|---|---|
| `Plan.md` | This document — implementation plan | ✓ exists |
| `Read.md` | Full documentation | ✓ exists (stub) |
| `activate.sh` | Finds node, labels it, applies stressor | **NEW** |
| `deactivate.sh` | Removes label, deletes stressor | **NEW** |
| `manifests/io-stress-daemonset.yaml` | DaemonSet restricting to the labeled node | **NEW** |

---

## Verification Plan

### Automated Checks
- `activate.sh` verifies the node was successfully labeled.
- `kubectl get pods -n teastore -l app=io-stress -o wide` confirms the stress pod is running on the correct node.

### Manual Verification
1. Access the Locust UI and begin load testing.
2. Execute `activate.sh`.
3. SSH into or run a temporary pod on the target node to run `iostat` or `dstat` and confirm disk utilization is at or near 100%.
4. Review Instana UI to verify the event is triggered and proper service topology correlation occurs.
5. Execute `deactivate.sh` to confirm resolution.
