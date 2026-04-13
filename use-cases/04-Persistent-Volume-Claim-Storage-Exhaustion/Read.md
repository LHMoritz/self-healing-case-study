# Goal of the Persistent Volume Claim Storage Exhaustion Scenario  
## Storage-Level Failure Evaluation

## 1. Purpose of the Experiment

The purpose of this scenario is to simulate storage exhaustion within a persistent volume claim in order to evaluate how the AI-agent-based observability platform interprets and contextualizes storage-related failures in a distributed application.

Storage exhaustion represents a frequent operational issue in containerized systems and may result in application crashes, write failures, or degraded functionality.

---

## 2. Conceptual Objective

This experiment assesses whether the observability system:

- Detects storage capacity violations in a timely manner,
- Associates storage-level telemetry with specific workloads,
- Identifies downstream effects such as application errors,
- Enables or suggests remediation actions such as volume resizing or workload restart.

The emphasis lies on understanding how storage-layer signals are integrated into a coherent incident narrative.

---

## 3. ITSM Perspective

From an ITSM perspective, this scenario activates:

- Incident Management,
- Problem Management (in cases of structural capacity constraints).

The experiment evaluates whether AI-supported observability contributes to faster diagnosis and improved handling of recurring storage-related incidents.

---

## 4. Architecture: Dynamic PVC Injection

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

**Stress mechanism:** A lightweight sidecar container (`volume-filler`) is injected alongside MariaDB in the same pod. It shares the exact same volume mount (`/var/lib/mysql`) pointing to a newly created `PersistentVolumeClaim`. The sidecar rapidly consumes 100% of the PVC's 1Gi capacity. Subsequent database writes will fail with `No space left on device`.

---

## 5. Experiment Execution

### Phase 1: Baseline
1.  Ensure Locust is running in the background to simulate traffic.
2.  Record baseline metrics in Instana (DB query success rate, standard response times).

### Phase 2: Inject Storage Exhaustion
1.  Run `./activate.sh`.
2.  The script creates a 1Gi PVC, binds the DB to it, and starts the sidecar.
3.  Within seconds, the PVC fills to 100%.
4.  Subsequent database write operations (e.g., new user sessions, cart additions) immediately fail.

### Phase 3: Observation
1.  Monitor Instana for an alert on **PVC Capacity Exhaustion**.
2.  Check if Instana correlates the storage alert to the `teastore-db` workload.
3.  Validate if the root cause analysis engine links the rising HTTP 500 error rate in the application to the underlying storage failure.

### Phase 4: Recovery
1.  Run `./deactivate.sh`.
2.  The DB deployment is reverted to ephemeral storage and the bloated PVC is deleted.
3.  Verify the application recovers and HTTP 500 errors cease in Locust.

---

## 6. Scripts & Manifests

| File | Purpose |
|---|---|
| `activate.sh` | Patches `teastore-db` to use a 1Gi PVC and injects the `volume-filler` sidecar. |
| `deactivate.sh` | Rolls back the `teastore-db` deployment and deletes the bloated PVC. |
| `manifests/db-pvc.yaml` | The 1Gi Persistent Volume Claim required for the test. |
| `manifests/storage-exhaustion-sidecar.yaml` | Strategic merge patch to inject the sidecar and mount the PVC. |