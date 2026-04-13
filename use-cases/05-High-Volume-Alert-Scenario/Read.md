# Goal of the High-Volume Alert Scenario  
## Alert Correlation and Noise Reduction Evaluation

## 1. Purpose of the Experiment

The purpose of this scenario is to simulate a high-volume alert situation in which approximately 200 alerts are generated simultaneously. The objective is to evaluate the AI-agent-based system’s ability to aggregate, prioritize, and contextualize large volumes of operational signals.

Alert floods are operationally critical because they increase cognitive load and delay effective incident resolution.

---

## 2. Conceptual Objective

This experiment aims to assess whether the observability platform:

- Aggregates related alerts into meaningful incident contexts,
- Identifies dominant root causes within large event sets,
- Reduces alert noise through intelligent correlation,
- Supports prioritization mechanisms for operational teams.

The focus is on evaluating AI-driven event consolidation rather than raw alert generation performance.

---

## 3. ITSM Perspective

From an ITSM perspective, this scenario primarily relates to:

- Monitoring and Event Management.

The experiment explores whether AI-agent-based observability improves operational efficiency by reducing manual triage effort and increasing clarity during high-pressure alert situations.

---

## 4. Architecture: Alert Flood

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

**Stress mechanism:** This scenario operates completely independently of the TeaStore application. We deploy a Kubernetes `Deployment` named `alert-flood` configured with exactly 200 replicas. The container specification intentionally executes an immediate `exit 1` command upon startup. 
When applied, the Kubernetes controller immediately attempts to spawn 200 pods, which all instantly fail, triggering a massive wave of 200 simultaneous `CrashLoopBackOff` events.

---

## 5. Experiment Execution

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

## 6. Scripts & Manifests

| File | Purpose |
|---|---|
| `activate.sh` | Deploys the 200-replica `alert-flood` manifest. |
| `deactivate.sh` | Deletes the `alert-flood` deployment to clean up the cluster. |
| `manifests/alert-flood.yaml` | The Deployment configured to spawn 200 instantly crashing BusyBox pods. |