# PVC Storage Exhaustion Scenario — Implementation Plan
## AKS + TeaStore + Storage Fill Job

This document describes the implementation plan for the **Persistent Volume Claim (PVC) Storage Exhaustion** experiment. The goal is to simulate a scenario where the application's underlying persistent storage runs out of capacity, a common issue in stateful containerized workloads that leads to application crashes or write failures.

In the typical TeaStore deployment, the `teastore-db` (MariaDB) service uses ephemeral node storage (`emptyDir`), not a Persistent Volume Claim (PVC). To test **PVC Storage Exhaustion** specifically, this experiment involves a two-step activation:
1.  **Inject a PVC:** We dynamically patch the `teastore-db` deployment so it stops using `emptyDir` and instead mounts a dedicated 1Gi `PersistentVolumeClaim`.
2.  **Saturate the PVC:** We simultaneously inject a sidecar container into the database pod that rapidly fills this newly attached PVC with dummy data until it reaches 100% capacity.

This scenario evaluates whether Instana can detect the storage capacity violation, associate the storage telemetry with the `teastore-db` workload, and identify the resulting application errors (such as failed database inserts from the `persistence` service) as downstream effects of the full volume.

---

## Architecture Overview

```
                    ┌─────────────────────────────────────────────────┐
                    │              AKS Cluster (<YOUR_CLUSTER_NAME>)          │
                    │                                                 │
                    │   ┌─────────────────────────────────────────┐  │
                    │   │  teastore-db Pod                        │  │
                    │   │  ┌──────────────┐  ┌─────────────────┐  │  │
                    │   │  │ teastore-db  │  │ volume-filler   │  │  │
                    │   │  │ (MariaDB)    │  │ (Sidecar)       │  │  │
                    │   │  │              │  │ dd if=/dev/zero │  │  │
                    │   │  └───────┬──────┘  └───────┬─────────┘  │  │
                    │   │          │                 │            │  │
                    │   │          ▼                 ▼            │  │
                    │   │      [ Shared Volume Mount /var/lib/mysql]  │  │
                    │   └────────────────────────────┬────────────┘  │
                    │                                │                │
                    │                      ┌─────────▼─────────┐      │
                    │                      │ teastore-db-pvc   │      │
                    │                      │ (1Gi limit)       │      │
                    │                      └───────────────────┘      │
                    │                                                 │
                    │   ┌─────────────────────────────────────────┐  │
                    │   │  teastore-persistence                   │  │
                    │   │  (Receives DB errors when writing)      │  │
                    │   └─────────────────────────────────────────┘  │
                    │                                                 │
                    │   ┌──────────────────┐                          │
                    │   │ Locust           │                          │
                    │   │ (Simulating users)                          │
                    │   └──────────────────┘                          │
                    └─────────────────────────────────────────────────┘
```

**Stress mechanism:** A lightweight sidecar container (e.g., busybox or Alpine) is injected alongside MariaDB. Because both containers share the exact same volume mount (`/var/lib/mysql`) pointing to the newly created PVC, the sidecar can use `dd` to rapidly consume 100% of the PVC's capacity. Any subsequent database write by MariaDB will fail with `No space left on device`.

---

## Step 1: Create Manifests for PVC and Sidecar Injection

We need two YAML files: one to create the PVC, and one containing the JSON/strategic merge patch for the `teastore-db` deployment.

### [NEW] `manifests/db-pvc.yaml`

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: teastore-db-pvc
  namespace: teastore
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

### [NEW] `manifests/storage-exhaustion-sidecar.yaml`

We will patch the existing database to switch its volume from `emptyDir` to the PVC, and add the sidecar.

```yaml
# Strategic merge patch for Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: teastore-db
spec:
  template:
    spec:
      containers:
      - name: volume-filler
        image: busybox
        # Fills the disk with a 950MB file (assuming 1Gi PVC)
        command: ["/bin/sh", "-c"]
        args:
          - |
            echo "Starting to fill volume..."
            dd if=/dev/zero of=/var/lib/mysql/bloat.dat bs=1M count=950
            echo "Volume filled. Sleeping to maintain state."
            sleep infinity
        volumeMounts:
        - name: teastore-db-volume-1
          mountPath: /var/lib/mysql
      volumes:
      - name: teastore-db-volume-1
        # Overwrite the emptyDir with our new PVC
        persistentVolumeClaim:
          claimName: teastore-db-pvc
        emptyDir: null
```

---

## Step 2: Create `activate.sh`

The activation script automates the setup.

1. **Verify Locust** — Ensure background traffic is running (Locust should already be active).
2. **Apply PVC** — Apply the `db-pvc.yaml` to create the 1Gi claim.
3. **Patch DB Deployment** — Apply the patch to map the DB to the PVC and inject the `volume-filler` sidecar.
4. **Wait & Print Status** — Wait for the new DB pod to roll out.

### Script Skeleton

```bash
#!/bin/bash
set -euo pipefail
NAMESPACE="${1:-teastore}"

echo "▸ Deploying 1Gi PVC for teastore-db..."
kubectl apply -f manifests/db-pvc.yaml -n "${NAMESPACE}"

echo "▸ Patching teastore-db to use PVC and injecting volume-filler sidecar..."
kubectl patch deployment teastore-db -n "${NAMESPACE}" --patch-file manifests/storage-exhaustion-sidecar.yaml

# Wait for rollout
kubectl rollout status deployment/teastore-db -n "${NAMESPACE}" --timeout=120s
```

---

## Step 3: Create `deactivate.sh`

The deactivation script cleans up the experiment and restores the database.

1. **Remove Sidecar & PVC Mount** — We use `kubectl rollout undo deployment/teastore-db` or a reverse patch to revert the database back to using `emptyDir` and remove the sidecar.
2. **Delete PVC** — Delete `teastore-db-pvc` to wipe the bloated data.
3. **Wait & Verify** — Ensure the database pod restarts cleanly with its original ephemeral storage configuration.

---

## Step 4: Expand `Read.md`

Expand the existing `Read.md` with:
- Architecture diagram showing the sidecar and shared PVC mount.
- Explanation of why we inject a PVC into TeaStore for this specific test.
- Step-by-step description of the experiment phases (assuming Locust is already running).
- Documentation of scripts and manifests used.
- Expected failure cascade description (PVC capacity hits 100% -> `teastore-db` fails to execute INSERT/UPDATE queries -> `teastore-persistence` throws exceptions -> Web UI returns 500 errors).

---

## Experiment Execution Sequence

### Phase 1: Baseline
1.  Ensure Locust is running in the background to simulate traffic.
2.  Record baseline metrics in Instana (DB query success rate, standard response times).

### Phase 2: Inject Storage Exhaustion
1.  Run `./activate.sh`.
2.  The script creates a 1Gi PVC, binds the DB to it, and starts the sidecar.
3.  Within seconds, the `dd` command fills the PVC to near 100%.
4.  Subsequent database write operations (e.g., new user sessions, cart additions) immediately fail.

### Phase 3: Observation
1.  Monitor Instana for an alert on **PVC Capacity Exhaustion**.
2.  Check if Instana correlates the storage alert to the `teastore-db` pod.
3.  Validate if the root cause analysis engine links the rising HTTP 500 error rate to the underlying storage failure.

### Phase 4: Recovery
1.  Run `./deactivate.sh`.
2.  The DB deployment is reverted to ephemeral storage and the PVC is deleted.
3.  Verify the application recovers and errors cease.

---

## Evaluation Criteria

| Criteria | Question |
|---|---|
| **Anomaly Detection** | Did Instana detect the PVC storage exhaustion? |
| **Service Correlation** | Were failed database queries explicitly linked to the lack of disk space? |
| **Topology Awareness** | Did Instana's topology graph map the PVC to the Pod, and the Pod to the Service? |
| **Root Cause** | Was the lack of storage capacity identified as the root cause of the application degradation? |
| **ITSM: Incident Mgmt** | Would this generate a clear, actionable incident for an infrastructure team? |
