# Visualization

This directory contains the configuration files for deploying **Grafana** and its dashboards.

## Dashboards

The Grafana instance is pre-configured with two main dashboards for monitoring the TeaStore application.

### 1. TeaStore Logs (`teastore-logs`)

This dashboard provides a centralized view of application logs collected via **Loki**.

*   **Data Source:** Loki
*   **Filters:**
    *   **Service:** Filter logs by the specific log filename (mapped to the service/container).
*   **Panels:**
    *   **Application Logs:** A scrollable log view showing the raw log lines with timestamps.

### 2. TeaStore Metrics (`teastore-metrics`)

This dashboard visualizes resource utilization metrics collected via **Prometheus** (OpenTelemetry Collector).

*   **Data Source:** Prometheus
*   **Filters:**
    *   **Namespace:** Select the Kubernetes namespace (Default: `default`).
    *   **Container:** Filter by container name to isolate specific microservices (e.g., `teastore-webui`, `teastore-db`).
*   **Panels:**
    *   **CPU Consumption:** Line graph showing the CPU utilization ratio over time for each pod matching the selected container.
    *   **Memory Usage:** Line graph showing the memory usage (in bytes) over time for each pod matching the selected container.

## Configuration

*   **`grafana.yaml`**: The main Kubernetes text manifest for deploying Grafana.
*   **`grafana-config.yaml`**: A ConfigMap containing:
    *   `grafana-datasources`: Defines Prometheus and Loki as data sources.
    *   `grafana-dashboard-provider`: Configures Grafana to load dashboards from files.
    *   `grafana-dashboards`: The JSON definitions for the logs and metrics dashboards.
