# Coprocessor Helm Chart

The `coprocessor` chart installs the runtime needed to accept HTTP ingestion traffic, compile and run RTBot SQL programs, and optionally push materialized-view results back to ThingsBoard.

This repository is the public release surface for RTBot coprocessor artifacts. It carries the public Helm chart and the GitHub Actions workflows that publish the chart to GHCR and mirror the public `rtbot-redis` image to `ghcr.io/rtbot-dev/rtbot-redis` without rebuilding it in this repo.

## What the chart installs

- one `StatefulSet`
- one SQL bootstrap `Job` that waits for the first `rtbot-redis` pod and loads packaged SQL into it
- one `rtbot-redis` container for RTBot execution and state
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
- RTBot SQL files to load, either inline or in an existing ConfigMap

## OCI distribution

The chart can be published as an OCI artifact to GHCR.

Pull a released chart locally:

```bash
helm pull oci://ghcr.io/rtbot-dev/helm-charts/coprocessor \
  --version 0.1.1
```

Install directly from GHCR:

```bash
helm install coprocessor oci://ghcr.io/rtbot-dev/helm-charts/coprocessor \
  --version 0.1.1 \
  --set-file sql.files.01-demo\.sql=./pipelines/01-demo.sql
```

If the package is private, authenticate first:

```bash
helm registry login ghcr.io -u <github-username>
```

## Minimum install

The base chart now assumes the common in-cluster setup: you already have ThingsBoard running in the same namespace, exposed as `http://thingsboard:8080`.

If that matches your cluster, the smallest install is just a release plus at least one SQL file:

```bash
helm install coprocessor . \
  --set-file sql.files.01-demo\.sql=./pipelines/01-demo.sql
```

Before installing, confirm the service name resolves the way the chart expects:

```bash
kubectl get svc thingsboard
```

If your ThingsBoard service has a different name, lives in another namespace, or is outside the cluster, keep reading and override `thingsboard.baseUrl` for that environment.

That install renders:

- the default ingress listener at `/ingest/{stream_name}`
- the default ThingsBoard target at `http://thingsboard:8080`
- persistent RTBot state in an `8Gi` PVC
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

For production, override the default ThingsBoard URL when either of these is true:

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

1. Inline SQL in `sql.files`.
2. An existing ConfigMap via `sql.existingConfigMap`.

Inline SQL is convenient for demos and tightly managed releases:

```yaml
sql:
  files:
    01-temperature.sql: |
      CREATE STREAM sensors (device_id DOUBLE PRECISION, temperature DOUBLE PRECISION);
```

Use `sql.existingConfigMap` when SQL is generated elsewhere, shared across releases, or too large to keep inside Helm values.

File names should end in `.sql`. The bootstrap Job runs each file in lexical order after the StatefulSet is created and the first Redis pod is reachable.

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

- name the ThingsBoard device with its access token, or
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
| SQL packaging | `sql.files`, `sql.existingConfigMap`, `sql.mountPath` |
| ThingsBoard | `thingsboard.baseUrl`, `thingsboard.existingSecret`, `thingsboard.existingSecretKey` |
| Connect ingress | `connect.ingress.*` |
| Connect egress | `connect.egress.*` |
| Secrets | `secret.create`, `secret.stringData`, `connect.extraEnvFrom`, `sqlRunner.extraEnvFrom`, `rtbotRedis.extraEnvFrom` |
| Persistence | `persistence.enabled`, `persistence.size`, `persistence.storageClassName`, `persistence.annotations` |
| Resources | `rtbotRedis.resources`, `connect.resources`, `sqlRunner.resources` |

If `values.schema.json` is present in your checkout, `helm lint` will also validate the core value structure.
