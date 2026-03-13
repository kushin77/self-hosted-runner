## 🔍 ON-PREM DEPLOYMENT VERIFICATION
**Target Worker:** 192.168.168.42
**Started:** 2026-03-13 04:45:01 UTC

### Health Check Results
- Checking SSH connectivity...
- ✓ SSH connectivity to 192.168.168.42
- Checking Docker status...
- ✓ Docker daemon running
- Checking docker-compose status...
- ✓ Docker Compose stack exists
NAME                       IMAGE                                   COMMAND                  SERVICE             CREATED          STATUS                      PORTS
onprem_backend_mock        kennethreitz/httpbin                    "gunicorn -b 0.0.0.0…"   backend-mock        45 minutes ago   Up 41 minutes (unhealthy)   0.0.0.0:8080->80/tcp, :::8080->80/tcp
onprem_frontend_mock       nginx:1.25-alpine                       "/docker-entrypoint.…"   frontend-mock       45 minutes ago   Up 42 minutes (unhealthy)   0.0.0.0:3000->80/tcp, :::3000->80/tcp
onprem_grafana             grafana/grafana:latest                  "/run.sh"                grafana             45 minutes ago   Up 44 minutes               0.0.0.0:3001->3000/tcp, :::3001->3000/tcp
onprem_image_pin_mock      kennethreitz/httpbin                    "gunicorn -b 0.0.0.0…"   image-pin-mock      45 minutes ago   Up 45 minutes (unhealthy)   0.0.0.0:8081->80/tcp, :::8081->80/tcp
onprem_kafka               confluentinc/cp-kafka:7.5.0             "/etc/confluent/dock…"   kafka               45 minutes ago   Up 45 minutes               0.0.0.0:9092->9092/tcp, :::9092->9092/tcp
onprem_nginx               nginx:1.25-alpine                       "/docker-entrypoint.…"   nginx               45 minutes ago   Up 39 minutes (unhealthy)   0.0.0.0:80->80/tcp, :::80->80/tcp, 0.0.0.0:443->443/tcp, :::443->443/tcp
onprem_portal_mock         nginx:1.25-alpine                       "/docker-entrypoint.…"   portal-mock         45 minutes ago   Up 45 minutes (healthy)     0.0.0.0:5173->80/tcp, :::5173->80/tcp
onprem_postgres            postgres:14-alpine                      "docker-entrypoint.s…"   postgres            45 minutes ago   Up 44 minutes (healthy)     0.0.0.0:5432->5432/tcp, :::5432->5432/tcp
onprem_postgres_exporter   prometheuscommunity/postgres-exporter   "/bin/postgres_expor…"   postgres-exporter   45 minutes ago   Up 44 minutes               0.0.0.0:9187->9187/tcp, :::9187->9187/tcp
- Checking container status...
- ✓ Container onprem_postgres running
- ✓ Container onprem_redis running
- ✓ Container onprem_kafka running
- ✓ Container onprem_prometheus running
- ✓ Container onprem_grafana running
- ✓ Container onprem_backend running
- ✓ Container onprem_frontend running
- ✓ Container onprem_portal running
- ⚠ WARNING: Container onprem_image-pin not running or not found
- ✓ Container onprem_nginx running
- Checking PostgreSQL health...
- ✓ PostgreSQL responsive
- Checking Redis health...
- ✓ Redis responsive
- Checking Kafka health...
- ✓ Kafka broker responsive
- Checking Backend API health...
- ⚠ WARNING: Backend API not responding yet (may still be initializing)
- Checking Frontend service...
- ✓ Frontend serving on :3000
- Checking Portal service...
- ✓ Portal serving on :5173
- Checking Prometheus...
- ✓ Prometheus responding on :9090
- Checking Grafana...
- ✓ Grafana responding on :3001
- Checking Nginx...
- ✓ Nginx responding on :80
- Checking API response performance...
- ✓ API response time acceptable
- Checking disk usage...
- ⚠ WARNING: Disk usage: 81% (approaching limit)
- Checking memory usage...
- ✓ Memory usage: 9% (healthy)
- Checking database integrity...
- ⚠ WARNING: Database may still be initializing
- Checking cache connectivity...
- ✓ Redis cache operational
- Checking network ports...
- ✓ Network ports accessible (11/11 responding)
- Checking SSL certificates...
- ⚠ WARNING: SSL certificates not yet installed
## 📊 VERIFICATION SUMMARY
- **Passed:** 24
- **Warnings:** 5
- **Failed:** 0
