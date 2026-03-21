# API Key Auth and Alarm Rules Provisioning — Design

## Goal

Switch ThingsBoard authentication from username/password to API keys (with backward-compatible fallback), and extend the demo bootstrap to provision alarm rules on the device profile so that computed telemetry from the coprocessor automatically triggers ThingsBoard alarms.

## Context

### Current state

- The demo bootstrap authenticates to ThingsBoard using admin username/password to create/reuse the demo device and fetch its access token.
- The egress pipeline pushes computed telemetry (e.g., `anomaly_score`, `temperature_avg_5`) to ThingsBoard using the device HTTP API (`POST /api/v1/{token}/telemetry`).
- ThingsBoard alarm rules live on **device profiles**. All devices sharing a profile share the same alarm rules. ThingsBoard's rule engine evaluates alarm conditions against incoming telemetry and handles the full alarm lifecycle (create, clear, acknowledge).
- ThingsBoard 4.3+ supports API keys (`X-Authorization: ApiKey <value>`) as a simpler, long-lived alternative to JWT.

### Key insight

We do NOT need a separate alarm egress pipeline. Since we already push computed telemetry, and ThingsBoard alarm rules evaluate against telemetry keys, we just need to provision alarm rules on the device profile at bootstrap time. ThingsBoard does the rest.

### Multi-device story

Device profiles are the natural grouping mechanism. One alarm rule on a profile applies to all devices in that profile. Our SQL already uses `GROUP BY device_id` to compute per-device signals independently. So:
- Write SQL once → computes per-device
- Set alarm rules on profile once → applies to all devices in that profile
- The chart automates this for the demo; production users use the TB UI or API

## Design decisions

### 1. API key authentication (primary) with username/password fallback

Add `thingsboard.apiKey` to `values.yaml`. When set, the bootstrap uses `X-Authorization: ApiKey <value>` for all TB API calls. When not set, fall back to the existing username/password flow.

Priority: API key > username/password. If both are provided, API key wins.

### 2. Demo alarm rules provisioned at bootstrap

The demo bootstrap job gains a new step after device creation: provision alarm rules on the `coprocessor-demo` device profile. The rules reference computed telemetry keys from the `demo_signals` materialized view.

Demo alarm rules:
- `high_anomaly_score`: WARNING when `anomaly_score > 10`, clear when `anomaly_score <= 10`

### 3. No new egress pipeline, no new file formats

This is an MVP. Alarm rules are hardcoded in the demo bootstrap Python script. Production users configure alarm rules via the TB UI against their computed telemetry keys, or via the TB API.

## Changes

### `values.yaml`

Add under `thingsboard`:
```yaml
thingsboard:
  baseUrl: http://thingsboard:8080
  apiKey: ""                    # NEW: ThingsBoard API key (preferred over admin credentials)
  existingSecret: ""
  existingSecretKey: THINGSBOARD_URL
```

Add under `demo`:
```yaml
demo:
  alarmRules:
    enabled: true               # NEW: provision alarm rules on device profile
```

### `templates/demo-bootstrap-job.yaml`

Add env var for API key:
```yaml
- name: DEMO_TB_API_KEY
  value: {{ .Values.thingsboard.apiKey | quote }}
```

### `templates/demo-configmap.yaml` — `bootstrap.py`

1. Add `tb_auth()` function: tries API key first, falls back to username/password JWT.
2. After device token is stored, if `DEMO_ALARM_RULES_ENABLED` is truthy:
   - Fetch the device profile for the demo device
   - Add alarm rules to `profileData.alarms`
   - Update the device profile via `POST /api/deviceProfile`

### `values.schema.json`

Add `thingsboard.apiKey` (string) and `demo.alarmRules.enabled` (boolean).

### `README.md`

- Update Quick Start to mention API key option
- Add "Alarm rules" section explaining the multi-device story
- Update Values guide table

### `templates/statefulset.yaml` and `templates/connect-configmap.yaml`

Pass `THINGSBOARD_API_KEY` env var to the connect container for future use (not consumed yet, but plumbed).

## What this does NOT do

- Does not add a separate alarm egress pipeline
- Does not add alarm rule YAML file format
- Does not manage device profiles in production (users do that via TB UI)
- Does not change the telemetry egress flow at all
- Does not modify RTBot or RTBot SQL
