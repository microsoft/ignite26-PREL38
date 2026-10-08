# Caldova application artifacts

This folder contains the Caldova portal, API, PostgreSQL seed, and reporting-worker workload.

## Container images

Both images use `src/` as the Docker build context:

```powershell
docker build -f src/portal/Dockerfile -t caldova-portal:local src
docker build -f src/api/Dockerfile -t caldova-api:local src
```

- `portal/` is the only web application reached through Application Gateway. It serves the learner workspace and proxies `/api/*` to the internal API.
- `api/` owns courses, assessments, quiz attempts, grade summaries, exports, and PostgreSQL health.
- `db/schema.sql` is an idempotent schema and deterministic healthy seed.
- `workload/seed.ps1` executes the checked-in seed inside the deployed API container, preserving the private PostgreSQL boundary.
- `reporting-worker/cloud-init.yaml` configures the VM's one-minute grade export and `caldova-reporting` Syslog heartbeat.

For local HTTP validation without PostgreSQL, run the API with `CALDOVA_DATA_MODE=memory`. Deployed environments intentionally default to PostgreSQL.
