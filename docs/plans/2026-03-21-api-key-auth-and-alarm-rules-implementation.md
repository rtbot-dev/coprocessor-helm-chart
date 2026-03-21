# API Key Auth and Alarm Rules Provisioning — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add API key authentication to ThingsBoard integration and extend demo bootstrap to provision alarm rules on the device profile.

**Architecture:** The demo bootstrap Python script gains a `tb_auth()` function that prefers API keys over username/password JWT. After creating/reusing the demo device and storing its token, the bootstrap provisions alarm rules on the device profile via the **Calculated Fields API** (`POST /api/calculatedField` with `type: "ALARM"`) — this is the "Actual" alarm system in ThingsBoard 4.3+. The bootstrap also cleans up any legacy alarm rules from the old `profileData.alarms` system. No new egress pipeline is needed — ThingsBoard's rule engine fires alarms based on computed telemetry.

**Tech Stack:** Helm chart templates (Go templates), Python (bootstrap script), ThingsBoard REST API, kubectl for verification.

---

### Task 1: Add API key and alarm rules values ✅ COMPLETED

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

### Task 2: Pass API key and alarm rules flag to demo bootstrap job ✅ COMPLETED

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

### Task 3: Update bootstrap.py — API key authentication ✅ COMPLETED

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

### Task 4: Update bootstrap.py — Alarm rules provisioning ✅ COMPLETED (revised approach)

> **Important discovery:** ThingsBoard 4.3 has TWO alarm rule systems:
> - **"Old" (legacy):** Uses `profileData.alarms` array on device profile JSON via `POST /api/deviceProfile`
> - **"Actual" (new):** Uses the **Calculated Fields API** via `POST /api/calculatedField` with `type: "ALARM"`
>
> The original plan used the legacy approach. During implementation, we discovered the TB UI creates rules
> via the "Actual" system. The bootstrap was rewritten to use `POST /api/calculatedField` and also cleans
> up any legacy rules.

**Files:**
- Modify: `templates/demo-configmap.yaml` (the `bootstrap.py` section)

**Step 1: Add `cleanup_legacy_alarm_rules()` function**

Removes any alarm rules from the legacy `profileData.alarms` array on the device profile:

```python
def cleanup_legacy_alarm_rules(auth_headers, device_profile_id):
    profile = tb_request("GET", "/api/deviceProfile/%s" % device_profile_id, auth_headers=auth_headers)
    alarms = profile.get("profileData", {}).get("alarms", [])
    if alarms:
        profile["profileData"]["alarms"] = []
        tb_request("POST", "/api/deviceProfile", payload=profile, auth_headers=auth_headers)
        log("cleaned up %d legacy alarm rule(s)" % len(alarms))
```

**Step 2: Add `provision_alarm_rules()` using calculatedField API**

Uses the "Actual" alarm system — `POST /api/calculatedField`:

```python
def provision_alarm_rules(auth_headers, device_profile_id):
    # Check if rule already exists (idempotent)
    existing = tb_request("GET",
        "/api/DEVICE_PROFILE/%s/calculatedFields?pageSize=100&page=0&sortProperty=createdTime&sortOrder=DESC&type=ALARM"
        % device_profile_id, auth_headers=auth_headers)
    for rule in existing.get("data", []):
        if rule.get("name") == "high_anomaly_score":
            log("alarm rule 'high_anomaly_score' already exists, skipping")
            return

    # Create alarm rule via calculatedField API
    alarm_payload = {
        "entityId": {"entityType": "DEVICE_PROFILE", "id": device_profile_id},
        "type": "ALARM",
        "name": "high_anomaly_score",
        "configuration": {
            "type": "ALARM",
            "arguments": {
                "anomaly_score": {
                    "refEntityKey": {"key": "anomaly_score", "type": "TS_LATEST"},
                    "defaultValue": ""
                }
            },
            "createRules": {
                "WARNING": {
                    "condition": {
                        "type": "SIMPLE",
                        "expression": {
                            "type": "SIMPLE",
                            "filters": [{
                                "argument": "anomaly_score",
                                "valueType": "NUMERIC",
                                "operation": "AND",
                                "predicates": [{
                                    "type": "NUMERIC",
                                    "operation": "GREATER",
                                    "value": {"staticValue": 10.0, "dynamicValueArgument": None}
                                }]
                            }],
                            "operation": "AND"
                        },
                        "schedule": None
                    },
                    "alarmDetails": None, "dashboardId": None
                }
            },
            "clearRule": {
                "condition": {
                    "type": "SIMPLE",
                    "expression": {
                        "type": "SIMPLE",
                        "filters": [{
                            "argument": "anomaly_score",
                            "valueType": "NUMERIC",
                            "operation": "AND",
                            "predicates": [{
                                "type": "NUMERIC",
                                "operation": "LESS_OR_EQUAL",
                                "value": {"staticValue": 10.0, "dynamicValueArgument": None}
                            }]
                        }],
                        "operation": "AND"
                    },
                    "schedule": None
                },
                "alarmDetails": None, "dashboardId": None
            },
            "propagate": False, "propagateToOwner": False, "propagateToTenant": False,
            "propagateRelationTypes": None, "output": None
        }
    }
    tb_request("POST", "/api/calculatedField", payload=alarm_payload, auth_headers=auth_headers)
    log("provisioned alarm rule 'high_anomaly_score' on device profile (Actual system)")
```

**Step 3: Call from main()**

Update `main()` to:
1. Call `tb_auth()` first
2. Pass auth headers to `ensure_demo_device_token()`
3. If `DEMO_ALARM_RULES_ENABLED` is truthy, fetch device to get `deviceProfileId`, clean up legacy rules, provision via calculatedField API

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
        cleanup_legacy_alarm_rules(auth_headers, profile_id)
        provision_alarm_rules(auth_headers, profile_id)
    return 0
```

**Step 4: Commit**

```bash
git add templates/demo-configmap.yaml
git commit --no-sign -m "feat: provision alarm rules via calculatedField API (Actual system)"
```

---

### Task 5: Update README and documentation ✅ COMPLETED

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

### Task 6: Deploy and verify end-to-end ✅ COMPLETED

**Step 1: Bump chart version**

Chart went through two versions:
- `0.3.0`: Initial API key auth + alarm rules (used legacy `profileData.alarms` approach)
- `0.3.1`: Fixed to use calculatedField API ("Actual" alarm system)

**Step 2: Commit, tag, push**

```bash
git commit --no-sign -m "fix: use calculatedField API for alarm rules (Actual system)"
git push origin main
git tag --no-sign coprocessor-chart-v0.3.1
git push origin coprocessor-chart-v0.3.1
```

**Step 3: CI published chart 0.3.1 successfully**

**Step 4: Created TB API key**

Created via ThingsBoard REST API (`POST /api/apiKey`), saved to `/tmp/tb_api_key_value.txt`.

**Step 5: Upgraded helm release**

```bash
helm upgrade coprocessor oci://ghcr.io/rtbot-dev/helm-charts/coprocessor \
  --version 0.3.1 \
  --namespace thingsboard \
  --set thingsboard.apiKey=<api-key>
```

Now at revision 5.

**Step 6: Verification results**

- ✅ Demo bootstrap job ran and completed (hook-succeeded auto-deleted the job)
- ✅ SQL bootstrap job ran and completed
- ✅ Alarm rule `high_anomaly_score` created via calculatedField API — confirmed via `GET /api/DEVICE_PROFILE/{id}/calculatedFields?type=ALARM`
- ✅ Legacy `profileData.alarms` is empty (cleanup worked)
- ✅ API key auth working — all API calls using `X-Authorization: ApiKey ...`
- ✅ Pipeline healthy: publisher → ingress → RTBot SQL → egress → ThingsBoard telemetry
- ⚠️ Alarms don't fire with smooth sine wave data — `anomaly_score` peaks at ~0.1, threshold is 10.0. This is **correct behavior** — the alarm rule is designed to detect real anomalies, not smooth signals.
