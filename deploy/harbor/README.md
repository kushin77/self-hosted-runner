# Harbor Helm chart (hardened scaffold)

This scaffold provides a minimal Harbor deployment (core + portal) with persistence and placeholders for DB, Redis, and Trivy scanner.

For production use, prefer the official Harbor Helm chart and configure:
- External PostgreSQL database
- Redis cache
- Trivy scanner integration
- TLS and ingress
- Persistent volumes and backups

This chart is intended as a starting point for integration testing and will be hardened in follow-up Draft issues.

Examples:
- `deploy/harbor/examples/postgres-secret.yaml` — template for external Postgres credentials.
- `deploy/harbor/examples/redis-secret.yaml` — template for Redis credentials.
- `deploy/harbor/examples/trivy-enable.md` — notes for enabling Trivy scanner integration.

Usage: update `values.yaml` to point to your external DB/Redis and enable `trivy.enabled=true` when you have a scanner endpoint configured.

Recommended flow (in-cluster example using the provided Terraform module):

1. Use the Terraform module that provisions Bitnami Postgres and creates the secret:

	 - `terraform/provision/postgres` will create a namespace (default `postgres`), install the Bitnami `postgresql` Helm release, generate a strong password, and write a Kubernetes secret named `harbor-db-password` by default.

2. Configure the chart to use the external DB by setting the values (either in `values.yaml` or via `--set`):

```yaml
database:
	type: postgres
	host: postgresql-postgresql.postgres.svc.cluster.local
	user: harbor
	passwordSecret: harbor-db-password
```

3. If you provision Postgres externally (managed DB) create the secret manually or via your tooling:

```yaml
apiVersion: v1
kind: Secret
metadata:
	name: harbor-db-password
stringData:
	password: "<YOUR_DB_PASSWORD>"
```

4. Install the chart: `helm install harbor ./deploy/harbor -f values.yaml`

Notes:
- The `passwordSecret` value expects the secret name in the same namespace where Harbor is installed.
- When using the Terraform module, the secret is created in the Postgres namespace; if you install Harbor in a different namespace you can either create the secret there (copy), or set `database.passwordSecret` to reference a secret in the Harbor namespace.

Redis integration (recommended for cache/session management):

1. Use the Redis Terraform module to provision an in-cluster Redis and create the secret:

	 - `terraform/provision/redis` will create the `redis` namespace, install the Bitnami `redis` Helm release, generate a strong password, and write a Kubernetes secret named `harbor-redis-password` by default.

2. Configure the chart to use the external Redis by setting the values:

```yaml
redis:
	enabled: false
	host: redis-redis.redis.svc.cluster.local
	passwordSecret: harbor-redis-password
```

3. If you provision Redis externally (managed Redis) create the secret manually or via your tooling:

```yaml
apiVersion: v1
kind: Secret
metadata:
	name: harbor-redis-password
stringData:
	password: "<YOUR_REDIS_PASSWORD>"
```

Notes:
- Ensure the `passwordSecret` is present in the namespace where Harbor is installed, or copy the secret into that namespace.
- The example values assume the Bitnami chart naming; update `host` to match the installed release DNS if you change release name/namespace.
