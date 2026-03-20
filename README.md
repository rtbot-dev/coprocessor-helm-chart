# Coprocessor Helm Chart

The `coprocessor` chart lets ThingsBoard users run RtBot SQL on live device telemetry without hand-wiring the runtime stack. Install it beside an existing ThingsBoard deployment, provide one or more SQL files, and the chart stands up the ingestion, execution, and optional egress path needed to turn raw telemetry into derived analytics.

This repository is the public release surface for the coprocessor Helm chart and the public `rtbot-redis` image.

## Why install it

Use this chart when you want to:

- run RtBot SQL against ThingsBoard telemetry in Kubernetes
- register SQL files as part of the deployment instead of managing ad-hoc runtime commands
- publish materialized-view results back into ThingsBoard
- start with a simple same-namespace install and grow into production overrides later

## Quick start

If you already have ThingsBoard running in the same namespace as a Service named `thingsboard`, the fastest path is:

```bash
helm install coprocessor oci://ghcr.io/rtbot-dev/helm-charts/coprocessor \
  --version 0.1.1 \
  --set-string sql.files.01-demo\.sql='CREATE STREAM sensors (device_id DOUBLE PRECISION, temperature DOUBLE PRECISION); CREATE MATERIALIZED VIEW latest_temperature AS SELECT device_id, MAX(temperature) AS temperature FROM sensors GROUP BY device_id;'
```

What this command is doing:

- installing the `coprocessor` chart next to your existing ThingsBoard service
- creating one SQL file inside the release named `01-demo.sql`
- filling that file with the RtBot SQL text you passed inline
- registering that SQL during the bootstrap job so the pipeline is ready to process telemetry

If you would rather keep the SQL in a local file instead of writing it inline, see [Simple and advanced SQL file input](#simple-and-advanced-sql-file-input).

## How to tell it worked

Run:

```bash
kubectl get pods,jobs
```

You should see:

- a `coprocessor` StatefulSet pod
- a SQL bootstrap Job

If those do not appear or do not become ready, continue with `tests/README.md` and the troubleshooting guidance in this repo.

## Table of contents

- [What the chart installs](#what-the-chart-installs)
- [Prerequisites](#prerequisites)
- [OCI distribution](#oci-distribution)
- [Minimum install](#minimum-install)
- [Demo install path](#demo-install-path)
- [Install smoke testing](#install-smoke-testing)
- [Production configuration guidance](#production-configuration-guidance)
- [SQL packaging guidance](#sql-packaging-guidance)
- [Ingress and egress guidance](#ingress-and-egress-guidance)
- [Values guide](#values-guide)

## What the chart installs

- one `StatefulSet`
- one SQL bootstrap `Job` that waits for the first `rtbot-redis` pod and loads packaged SQL into it
- one `rtbot-redis` container for RtBot execution and state
- one Redpanda Connect container for ingress and optional egress wiring
- one headless `Service` for the StatefulSet and one client-facing ingress `Service`
- generated `ConfigMap` objects for SQL and Connect config unless you point at existing ones
- an optional generated `Secret`
- a persistent volume claim by default

## Prerequisites

- Kubernetes cluster with Helm 3
- an existing ThingsBoard deployment that is reachable from this namespace
- a StorageClass if `persistence.enabled=true`
- an `rtbot-redis` image pull path that is valid for your environment; the chart default is `ghcr.io/rtbot-dev/rtbot-redis`
- RtBot SQL files to load, either inline or in an existing ConfigMap

## OCI distribution

The chart is published as an OCI artifact to GHCR.

Pull a released chart locally:

```bash
helm pull oci://ghcr.io/rtbot-dev/helm-charts/coprocessor \
  --version 0.1.1
```

Install directly from GHCR:

```bash
helm install coprocessor oci://ghcr.io/rtbot-dev/helm-charts/coprocessor \
  --version 0.1.1 \
  --set-string sql.files.01-demo\.sql='CREATE STREAM sensors (device_id DOUBLE PRECISION, temperature DOUBLE PRECISION); CREATE MATERIALIZED VIEW latest_temperature AS SELECT device_id, MAX(temperature) AS temperature FROM sensors GROUP BY device_id;'
```

## Minimum install

The base chart assumes the common in-cluster setup: you already have ThingsBoard running in the same namespace, exposed as `http://thingsboard:8080`.

If that matches your cluster, the smallest install from the repository root is:

```bash
helm install coprocessor . \
  --set-string sql.files.01-demo\.sql='CREATE STREAM sensors (device_id DOUBLE PRECISION, temperature DOUBLE PRECISION); CREATE MATERIALIZED VIEW latest_temperature AS SELECT device_id, MAX(temperature) AS temperature FROM sensors GROUP BY device_id;'
```

Before installing, confirm the service name resolves the way the chart expects:

```bash
kubectl get svc thingsboard
```

If your ThingsBoard service has a different name, lives in another namespace, or is outside the cluster, override `thingsboard.baseUrl` for that environment.

That install renders:

- the default ingress listener at `/ingest/{stream_name}`
- the default ThingsBoard target at `http://thingsboard:8080`
- persistent RtBot state in an `8Gi` PVC
- a post-install/post-upgrade SQL bootstrap Job
- no generated secret unless `secret.create=true`
- no egress pipeline unless `connect.egress.enabled=true`

## Demo install path

`values-demo.yaml` is the low-friction walkthrough profile. It keeps the same-namespace ThingsBoard default from the base chart, disables persistence so clusters without a default StorageClass still work, and embeds a tiny SQL example.

```bash
helm install coprocessor-demo . \
  -f values-demo.yaml
```

Use the demo profile when you want a fast walkthrough. Use base `values.yaml` when you already have ThingsBoard running in the namespace and only need to supply SQL. Reserve explicit URL overrides for production variants such as cross-namespace or external ThingsBoard deployments.

## Install smoke testing

A first install harness now exists at `tests/install-smoke.sh`.

It is intentionally conservative:

- it targets local `kind` or `minikube` contexts by default
- it refuses to use an arbitrary reachable `kubectl` context unless `ALLOW_NONLOCAL_CONTEXT=1`
- it validates the narrow same-namespace install path only

See `tests/README.md` for details and the list of `#480` scenarios that still require broader validation.

## Production configuration guidance

For production, treat these as the main override points:

- `images.*`: pin repositories and tags that match your registry policy; the base chart defaults `images.rtbotRedis.repository` to `ghcr.io/rtbot-dev/rtbot-redis`
- `rtbotRedis.resources`, `connect.resources`, `sqlRunner.resources`: set requests and limits explicitly
- `persistence.size`, `persistence.storageClassName`, `persistence.annotations`: match your storage tier
- `commonLabels`, `commonAnnotations`, `service.labels`, `statefulset.annotations`, `podAnnotations`: integrate with cluster policy and inventory tooling
- `nodeSelector`, `tolerations`, `affinity`: place workloads onto the right nodes
- `connect.extraEnvFrom`, `sqlRunner.extraEnvFrom`, `rtbotRedis.extraEnvFrom`: reference existing Secrets or ConfigMaps for environment-driven settings
- `thingsboard.existingSecret` and `thingsboard.existingSecretKey`: source `THINGSBOARD_URL` from an existing Secret instead of plain values

Override the default ThingsBoard URL when either of these is true:

- ThingsBoard lives in a different namespace, for example `http://thingsboard.other-namespace.svc.cluster.local:8080`
- ThingsBoard is reached through an external URL such as `https://thingsboard.example.com`

Example production-oriented install:

```bash
helm install coprocessor . \
  --set thingsboard.baseUrl=https://thingsboard.example.com \
  --set persistence.size=50Gi \
  --set persistence.storageClassName=fast-ssd \
  --set rtbotRedis.resources.requests.cpu=500m \
  --set rtbotRedis.resources.requests.memory=1Gi \
  --set connect.resources.requests.cpu=250m \
  --set connect.resources.requests.memory=512Mi
```

## SQL packaging guidance

The chart supports two SQL packaging modes:

1. inline SQL in `sql.files`
2. an existing ConfigMap via `sql.existingConfigMap`

Inline SQL is convenient for demos and tightly managed releases:

```yaml
sql:
  files:
    01-temperature.sql: |
      CREATE STREAM sensors (device_id DOUBLE PRECISION, temperature DOUBLE PRECISION);
```

Use `sql.existingConfigMap` when SQL is generated elsewhere, shared across releases, or too large to keep inside Helm values.

### Simple and advanced SQL file input

Use `sql.files` for the low-friction path. It keeps `--set-file` working and is the easiest way to package SQL with a release:

```bash
helm install coprocessor . \
  --set-file sql.files.01-bootstrap\.sql=./sql/01-bootstrap.sql \
  --set-file sql.files.02-views\.sql=./sql/02-views.sql
```

In that example, each `--set-file sql.files.<name>.sql=...` argument creates one SQL file inside the release and fills it with the contents of your local file.

```yaml
sql:
  files:
    01-bootstrap.sql: |
      CREATE STREAM sensors (device_id DOUBLE PRECISION, temperature DOUBLE PRECISION);
    02-views.sql: |
      CREATE MATERIALIZED VIEW latest_temperature AS
      SELECT device_id, MAX(temperature) AS temperature
      FROM sensors
      GROUP BY device_id;
```

Use `sql.selectedFiles` for the advanced path when the mounted SQL directory contains more files than you want to execute, or when you need a custom execution order. This works with either `sql.files` or `sql.existingConfigMap`, but it is especially useful with shared pre-created ConfigMaps:

```yaml
sql:
  existingConfigMap: shared-coprocessor-sql
  selectedFiles:
    - 20-schema.sql
    - 40-backfill.sql
    - 99-views.sql
```

Execution rules:

- if `sql.selectedFiles` is empty, the bootstrap Job runs every `*.sql` file from the mounted SQL directory in lexical order
- if `sql.selectedFiles` is non-empty, the bootstrap Job runs only those files, in the exact listed order
- if `sql.selectedFiles` includes a missing file or a file that does not end in `.sql`, the bootstrap Job fails fast with a clear error

File names should end in `.sql`. The bootstrap Job runs after the StatefulSet is created and the first Redis pod is reachable.

If you are installing next to an existing ThingsBoard instance, the usual first pass is:

1. keep `thingsboard.baseUrl` at its default
2. provide one or more SQL files
3. optionally enable egress once you are ready to publish materialized views back to ThingsBoard

## Ingress and egress guidance

### Ingress

Ingress traffic lands on the chart `Service` and is handled by Redpanda Connect.

- HTTP path: `connect.ingress.path`
- allowed methods: `connect.ingress.allowedVerbs`
- request timeout: `connect.ingress.timeout`
- device header: `connect.ingress.deviceIdHeader`
- timestamp header: `connect.ingress.timestampHeader`
- Redis stream backpressure: `connect.ingress.maxInFlight`
- Redis stream trimming: `connect.ingress.maxStreamLength`

The default path is `/ingest/{stream_name}`. The caller chooses the stream name through that path parameter.

### Egress

Enable egress with `connect.egress.enabled=true`.

Important settings:

- `connect.egress.stream` or `connect.egress.streams`
- `connect.egress.consumerGroup`
- `connect.egress.clientId`
- `connect.egress.startFromOldest`
- `connect.egress.commitPeriod`
- `connect.egress.retries`
- `connect.egress.retryPeriod`
- `connect.egress.timeout`

If egress is enabled, the chart renders an additional Connect pipeline that reads Redis streams and POSTs telemetry to ThingsBoard.

#### Device token prerequisite

The egress pipeline resolves the ThingsBoard device token this way:

1. reverse-lookup the numeric device hash in `coprocessor:device_map`
2. use the resulting device name to look up `coprocessor:device_tokens`
3. if no token mapping exists, fall back to using the device name itself as the token

That means you must choose one of these operating models:

- name the ThingsBoard device with its access token
- populate the Redis hash `coprocessor:device_tokens` with `device_name -> device_token`

The chart does not currently manage `coprocessor:device_tokens` for you.

## Values guide

High-value fields to review before every install:

| Area | Keys |
| --- | --- |
| Naming | `nameOverride`, `fullnameOverride` |
| Images | `images.rtbotRedis.*`, `images.connect.*`, `images.sqlRunner.*` |
| Placement | `nodeSelector`, `tolerations`, `affinity` |
| Metadata | `commonLabels`, `commonAnnotations`, `podLabels`, `podAnnotations` |
| Services | `service.*`, `headlessService.*` |
| SQL packaging | `sql.files`, `sql.selectedFiles`, `sql.existingConfigMap`, `sql.mountPath` |
| ThingsBoard | `thingsboard.baseUrl`, `thingsboard.existingSecret`, `thingsboard.existingSecretKey` |
| Connect ingress | `connect.ingress.*` |
| Connect egress | `connect.egress.*` |
| Secrets | `secret.create`, `secret.stringData`, `connect.extraEnvFrom`, `sqlRunner.extraEnvFrom`, `rtbotRedis.extraEnvFrom` |
| Persistence | `persistence.enabled`, `persistence.size`, `persistence.storageClassName`, `persistence.annotations` |
| Resources | `rtbotRedis.resources`, `connect.resources`, `sqlRunner.resources` |

If `values.schema.json` is present in your checkout, `helm lint` also validates the core value structure.
