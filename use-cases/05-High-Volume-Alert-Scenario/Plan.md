# High-Volume Alert Scenario — Implementation Plan
## AKS + Alert Flood Deployment

This document describes the implementation plan for the **High-Volume Alert** experiment. The goal is to simulate approximately 200 simultaneous pod crashes to evaluate how the AI-agent-based observability platform behaves under extreme load.

Alert floods drastically increase cognitive load and delay incident resolution for operations teams. This scenario specifically aims to discover **what Instana does in these situations, how its algorithms group the events, and critically, how it prioritizes them.**

**Decoupled Architecture:** This scenario operates completely independently of the TeaStore application. We will achieve the alert flood by deploying a Kubernetes object that intentionally fails at scale.

---

## Architecture Overview

```
                    ┌─────────────────────────────────────────────────┐
                    │              AKS Cluster (<YOUR_CLUSTER_NAME>)          │
                    │                                                 │
                    │   ┌─────────────────────────────────────────┐  │
                    │   │  Namespace: teastore                    │  │
                    │   │                                         │  │
                    │   │  ┌───────────────────────────────────┐  │  │
                    │   │  │ alert-flood Deployment            │  │  │
                    │   │  │ (Replicas: 200)                   │  │  │
                    │   │  │                                   │  │  │
                    │   │  │  [Pod 1]  [Pod 2] ... [Pod 200]   │  │  │
                    │   │  │  (Crash)  (Crash)     (Crash)     │  │  │
                    │   │  └───────────────────────────────────┘  │  │
                    │   └─────────────────────────────────────────┘  │
                    └─────────────────────────────────────────────────┘
```

**Stress mechanism:** We will create a Kubernetes `Deployment` named `alert-flood` configured with **200 replicas**. The container specification will intentionally be flawed (e.g., executing an immediate `exit 1` command or referencing a non-existent container image). 
When this is applied, the Kubernetes ReplicaSet controller will immediately attempt to spawn 200 pods. All 200 pods will instantly fail, triggering a massive wave of 200 simultaneous `CrashLoopBackOff` or `ErrImagePull` events.

This is a pure infrastructure-level event flood that perfectly mimics a massive configuration rollout failure.

---

## Step 1: Create the Alert Flood Manifest

We will create a single manifest defining the failing deployment.

### [NEW] `manifests/alert-flood.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: alert-flood
  namespace: teastore
  labels:
    app: alert-flood
spec:
  replicas: 200
  selector:
    matchLabels:
      app: alert-flood
  template:
    metadata:
      labels:
        app: alert-flood
    spec:
      containers:
      - name: crasher
        image: busybox
        # Intentionally crash immediately to trigger CrashLoopBackOff at scale
        command: ["/bin/sh", "-c", "echo 'Simulating fatal error'; exit 1"]
        resources:
          requests:
            cpu: "10m"
            memory: "10Mi"
```

---

## Step 2: Create `activate.sh`

The activation script automates the deployment of the massive failing workload.

1. **Deploy Flood** — Apply the `alert-flood.yaml` manifest.
2. **Status Check** — Print instructions on how to observe the 200 failing pods in Kubernetes and Instana.

### Script Skeleton

```bash
#!/bin/bash
set -euo pipefail
NAMESPACE="${1:-teastore}"

echo "▸ Deploying Alert Flood (200 failing replicas)..."
kubectl apply -f manifests/alert-flood.yaml -n "${NAMESPACE}"

echo "Deployment submitted. Kubernetes is now scheduling 200 pods that will instantly fail."
```

---

## Step 3: Create `deactivate.sh`

The deactivation script cleans up the experiment, sending a massive "resolve" signal cascade.

1. **Delete Flood** — Delete the `alert-flood` deployment.
2. **Wait & Verify** — Ensure all 200 pods are terminated and the namespace is clean.

---

## Step 4: Expand `Read.md`

Expand the existing `Read.md` with:
- Architecture diagram showing the 200 replica deployment.
- Step-by-step description of the experiment phases.
- Documentation of scripts and manifests used.
- Expected outcome description (200 Pods enter CrashLoopBackOff -> Instana aggregates these 200 individual pod alerts into 1 major Incident linked to the `alert-flood` Deployment).

---

## Experiment Execution Sequence

### Phase 1: Baseline
1.  Record baseline alert state in Instana (Cluster should be relatively quiet).

### Phase 2: Inject Alert Flood
1.  Run `./activate.sh`.
2.  The script deploys the 200-replica `alert-flood` deployment.
3.  Within 10-20 seconds, the cluster generates hundreds of scheduling and crashing events.

### Phase 3: Observation
1.  Monitor the Instana Events/Incidents dashboard.
2.  **Evaluate Behavior & Aggregation:** Observe exactly what Instana does. Does it create 200 isolated, standalone alerts (bad), or does it aggregate them into a single, grouped incident indicating that the `alert-flood` deployment is failing (good)?
3.  **Evaluate Prioritization:** Analyze the assigned severity and priority of the resulting alert(s). Does Instana recognize this as a critical cluster-level issue due to the sheer volume, or does it rank it low because it's just a failing dummy workload? How does it weigh the volume versus the impact?
4.  Verify the ITSM value: What kind of ticket logic would result from this behavior in a connected ITSM system?

### Phase 4: Recovery
1.  Run `./deactivate.sh`.
2.  The `alert-flood` deployment is deleted, removing all 200 crashing pods.
3.  Verify the incident automatically resolves in Instana.

---

## Evaluation Criteria

| Criteria | Question |
|---|---|
| **System Behavior** | How did Instana initially react to the sudden flood of 200 events? |
| **Event Aggregation** | Did Instana group the 200 pod failures into a single incident/alert group, or leave them as individual noise? |
| **Prioritization Logic** | How did Instana prioritize the event? Which severity level was assigned and why? |
| **Contextualization** | Did the alert properly identify the parent `Deployment` resource as the root cause rather than just listing individual pods? |
| **ITSM: Event Mgmt** | Would this aggregation and prioritization logic effectively prevent an alert storm in a connected ITSM ticking system? |
