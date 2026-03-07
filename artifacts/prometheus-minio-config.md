# Prometheus MinIO Scrape Configuration
# Add this section to your Prometheus prometheus.yml file
# Location: /etc/prometheus/prometheus.yml or deployment-specific path

global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'production'
    region: 'us-east-1'

# Add this scrape config for MinIO metrics
scrape_configs:
  - job_name: 'minio'
    # Customize this to match your MinIO deployment
    # Default: http://minio:9000 (docker) or http://localhost:9000 (local)
    # Production: https://minio.example.com:9000
    static_configs:
      - targets: ['mc.elevatediq.ai:9000']
        labels:
          service: 'minio'
          environment: 'production'
    metrics_path: '/minio/v2/metrics/cluster'
    scheme: 'https'
    scrape_interval: 30s
    scrape_timeout: 10s
    
    # Optional: Authentication (if MinIO requires credentials)
    # basic_auth:
    #   username: 'username'
    #   password: 'password'
    
    # Optional: TLS Configuration
    tls_config:
      insecure_skip_verify: false  # Set to true if using self-signed certificates
    
    # Optional: Relabeling for dynamic scraping
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
      - source_labels: [service]
        target_label: job

  # Optional: Add Node Exporter for MinIO host metrics
  - job_name: 'minio-node'
    static_configs:
      - targets: ['mc.elevatediq.ai:9100']
    metrics_path: '/metrics'
    scrape_interval: 15s

  # Optional: Add additional exporters (e.g., node_exporter on MinIO host)
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['mc.elevatediq.ai:9100']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance

---

# For Kubernetes Deployments (if using Prometheus Operator)
# Use this ServiceMonitor instead:

apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: minio-metrics
  namespace: minio
spec:
  selector:
    matchLabels:
      app: minio
  endpoints:
    - port: metrics
      interval: 30s
      path: /minio/v2/metrics/cluster
      scheme: https
      tlsConfig:
        insecureSkipVerify: false
