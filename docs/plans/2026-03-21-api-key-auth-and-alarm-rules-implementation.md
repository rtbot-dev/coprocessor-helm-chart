# API Key Auth and Alarm Rules Provisioning — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add API key authentication to ThingsBoard integration and extend demo bootstrap to provision alarm rules on the device profile.

**Architecture:** The demo bootstrap Python script gains a `tb_auth()` function that prefers API keys over username/password JWT. After creating/reusing the demo device and storing its token, the bootstrap provisions alarm rules on the device profile via `POST /api/deviceProfile`. No new egress pipeline is needed — ThingsBoard's rule engine fires alarms based on computed telemetry.

**Tech Stack:** Helm chart templates (Go templates), Python (bootstrap script), ThingsBoard REST API, kubectl for verification.

---

### Task 1: Add API key and alarm rules values

**Files:**
- Modify: `values.yaml`
- Modify: `values.schema.json`

**Step 1: Add `thingsboard.apiKey` to values.yaml**

In `values.yaml`, add `apiKey: ""` under the `thingsboard` section, after `baseUrl`:

```yaml
thingsboard:
  baseUrl: http://thingsboard:8080
  apiKey: ""
  existingSecret: ""
  existingSecretKey: THINGSBOARD_URL
```

**Step 2: Add `demo.alarmRules.enabled` to values.yaml**

In `values.yaml`, add `alarmRules` under the `demo` section, after `egressStreams`:

```yaml
demo:
  enabled: true
  sqlFileName: 00-demo.sql
  ingressStream: demo_sensors
  egressStreams:
    - rtbot:mv:demo_signals
  alarmRules:
    enabled: true
  device:
    ...
```

**Step 3: Add both to values.schema.json**

Add `apiKey` to the `thingsboard` properties:

```json
"apiKey": {
  "type": "string"
}
```

Add `alarmRules` to the `demo` properties:

```json
"alarmRules": {
  "type": "object",
  "properties": {
    "enabled": {
      "type": "boolean"
    }
  }
}
```

**Step 4: Run helm lint to validate**

Run: `helm lint .` in the chart directory.
Expected: `0 errors`

**Step 5: Commit**

```bash
git add values.yaml values.schema.json
git commit --no-sign -m "feat: add thingsboard.apiKey and demo.alarmRules values"
```

---

### Task 2: Pass API key and alarm rules flag to demo bootstrap job

**Files:**
- Modify: `templates/demo-bootstrap-job.yaml`

**Step 1: Add DEMO_TB_API_KEY env var**

After the `DEMO_ADMIN_PASSWORD` env block (line ~83), add:

```yaml
            - name: DEMO_TB_API_KEY
              value: {{ .Values.thingsboard.apiKey | quote }}
            - name: DEMO_ALARM_RULES_ENABLED
              value: {{ .Values.demo.alarmRules.enabled | quote }}
```

**Step 2: Run helm template to validate rendering**

Run: `helm template test . | grep -A2 DEMO_TB_API_KEY`
Expected: shows the env var with empty string default

Run: `helm template test . | grep -A2 DEMO_ALARM_RULES_ENABLED`
Expected: shows the env var with `"true"` default

**Step 3: Commit**

```bash
git add templates/demo-bootstrap-job.yaml
git commit --no-sign -m "feat: pass API key and alarm rules flag to demo bootstrap"
```

---

### Task 3: Update bootstrap.py — API key authentication

**Files:**
- Modify: `templates/demo-configmap.yaml` (the `bootstrap.py` section)

**Step 1: Add `tb_auth()` function**

Replace the inline JWT login logic in `ensure_demo_device_token()` with a reusable `tb_auth()` function. The function:
1. Checks `DEMO_TB_API_KEY` env var. If non-empty, returns `{"X-Authorization": "ApiKey <value>"}` headers.
2. Otherwise, checks `DEMO_ADMIN_USERNAME` and `DEMO_ADMIN_PASSWORD`. If both set, does JWT login and returns `{"X-Authorization": "Bearer <token>"}` headers.
3. If neither, returns `None`.

Replace the current `ensure_demo_device_token` function to use `tb_auth()`:

```python
def tb_auth():
    api_key = os.environ.get("DEMO_TB_API_KEY", "").strip()
    if api_key:
        log("using ThingsBoard API key authentication")
        return {"X-Authorization": "ApiKey %s" % api_key}
    username, password = get_admin_credentials()
    if username and password:
        log("using ThingsBoard username/password authentication")
        login_response = tb_request(
            "POST",
            "/api/auth/login",
            {"username": username, "password": password},
        )
        return {"X-Authorization": "Bearer %s" % login_response["token"]}
    return None
```

Update `tb_request` to accept an `auth_headers` dict instead of a `bearer_token` string.

Update `ensure_demo_device_token` to use the new `tb_auth()` and pass the auth headers through.

**Step 2: Validate with helm template**

Run: `helm template test . | grep -A5 "def tb_auth"`
Expected: shows the new function in the rendered configmap

**Step 3: Commit**

```bash
git add templates/demo-configmap.yaml
git commit --no-sign -m "feat: add API key auth with username/password fallback in bootstrap"
```

---

### Task 4: Update bootstrap.py — Alarm rules provisioning

**Files:**
- Modify: `templates/demo-configmap.yaml` (the `bootstrap.py` section)

**Step 1: Add `provision_alarm_rules()` function**

After `ensure_demo_device_token()`, add:

```python
def provision_alarm_rules(auth_headers, device_profile_id):
    profile = tb_request("GET", "/api/deviceProfile/%s" % device_profile_id, auth_headers=auth_headers)
    alarm_rules = [
        {
            "id": "high_anomaly_score",
            "alarmType": "high_anomaly_score",
            "createRules": {
                "WARNING": {
                    "condition": {
                        "condition": [
                            {
                                "key": {"type": "TIME_SERIES", "key": "anomaly_score"},
                                "valueType": "NUMERIC",
                                "predicate": {
                                    "type": "NUMERIC",
                                    "operation": "GREATER",
                                    "value": {"defaultValue": 10.0, "userValue": None, "dynamicValue": None},
                                },
                            }
                        ],
                        "spec": {"type": "SIMPLE"},
                    },
                    "schedule": None,
                    "alarmDetails": None,
                    "dashboardId": None,
                }
            },
            "clearRule": {
                "condition": {
                    "condition": [
                        {
                            "key": {"type": "TIME_SERIES", "key": "anomaly_score"},
                            "valueType": "NUMERIC",
                            "predicate": {
                                "type": "NUMERIC",
                                "operation": "LESS_OR_EQUAL",
                                "value": {"defaultValue": 10.0, "userValue": None, "dynamicValue": None},
                            },
                        }
                    ],
                    "spec": {"type": "SIMPLE"},
                },
                "schedule": None,
                "alarmDetails": None,
                "dashboardId": None,
            },
            "propagate": False,
            "propagateToOwner": False,
            "propagateToTenant": False,
            "propagateRelationTypes": [],
        }
    ]
    profile["profileData"]["alarms"] = alarm_rules
    tb_request("POST", "/api/deviceProfile", payload=profile, auth_headers=auth_headers)
    log("provisioned alarm rule 'high_anomaly_score' on device profile")
```

**Step 2: Call from main()**

Update `main()` to:
1. Call `tb_auth()` first
2. Pass auth headers to `ensure_demo_device_token()`
3. If `DEMO_ALARM_RULES_ENABLED` is truthy, also fetch the device to get its `deviceProfileId`, then call `provision_alarm_rules()`

```python
def main():
    wait_for_redis()
    auth_headers = tb_auth()
    device_token, device_id = ensure_demo_device_token(auth_headers)
    if device_token:
        redis_set_device_token(os.environ["DEMO_DEVICE_NAME"], device_token)
    alarm_rules_enabled = os.environ.get("DEMO_ALARM_RULES_ENABLED", "").lower() in ("true", "1", "yes")
    if alarm_rules_enabled and auth_headers and device_id:
        device = tb_request("GET", "/api/device/%s" % device_id, auth_headers=auth_headers)
        profile_id = device["deviceProfileId"]["id"]
        provision_alarm_rules(auth_headers, profile_id)
    return 0
```

Note: `ensure_demo_device_token` needs to return both the token and the device_id.

**Step 3: Validate with helm template**

Run: `helm template test . | grep "provision_alarm_rules\|alarm_rules"`
Expected: shows the function and env var reference

**Step 4: Commit**

```bash
git add templates/demo-configmap.yaml
git commit --no-sign -m "feat: provision alarm rules on device profile at demo bootstrap"
```

---

### Task 5: Update README and documentation

**Files:**
- Modify: `README.md`

**Step 1: Update Quick Start section**

Add API key example alongside existing credential examples:

```bash
helm upgrade --install coprocessor oci://ghcr.io/rtbot-dev/helm-charts/coprocessor \
  --version 0.3.0 \
  --namespace thingsboard \
  --set thingsboard.apiKey=<your-api-key>
```

**Step 2: Add "Alarm rules" section**

After "Ingress and egress guidance", add a section explaining:
- The demo automatically provisions alarm rules on the device profile
- Alarm rules evaluate against computed telemetry keys (e.g., `anomaly_score`)
- Multi-device: all devices sharing a profile get the same alarm rules
- Production users configure alarm rules via TB UI against their computed telemetry keys

**Step 3: Update Values guide table**

Add `thingsboard.apiKey` row and `demo.alarmRules.*` row.

**Step 4: Commit**

```bash
git add README.md
git commit --no-sign -m "docs: add API key auth and alarm rules documentation"
```

---

### Task 6: Deploy and verify end-to-end

**Step 1: Bump chart version**

Update `Chart.yaml` version to `0.3.0`.

**Step 2: Commit, tag, push**

```bash
git add Chart.yaml
git commit --no-sign -m "chore: bump chart version to 0.3.0"
git push origin main
git tag --no-sign coprocessor-chart-v0.3.0
git push origin coprocessor-chart-v0.3.0
```

**Step 3: Wait for CI**

Watch `gh run list --repo rtbot-dev/coprocessor-helm-chart` until publish completes.

**Step 4: Create TB API key in cluster**

Use kubectl to call TB API: create an API key in ThingsBoard for the tenant.

**Step 5: Upgrade helm release**

```bash
helm upgrade coprocessor oci://ghcr.io/rtbot-dev/helm-charts/coprocessor \
  --version 0.3.0 \
  --namespace thingsboard \
  --set thingsboard.apiKey=<api-key>
```

**Step 6: Verify alarm rules provisioned**

Check the device profile in ThingsBoard has the `high_anomaly_score` alarm rule.

**Step 7: Verify alarms fire**

Wait for the demo publisher to push enough data that `anomaly_score` exceeds 10 (happens at temperature peaks), then check that alarms appear in the ThingsBoard Alarms tab.

**Step 8: Verify alarms clear**

When `anomaly_score` drops below 10, confirm the alarm is cleared in ThingsBoard.
