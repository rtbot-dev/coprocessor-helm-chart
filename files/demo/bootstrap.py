import json
import os
import sys
import time
import urllib.error
import urllib.request


def log(message):
    print("[demo-bootstrap] %s" % message, flush=True)


def redis_request(parts):
    host = os.environ["REDIS_HOST"]
    port = int(os.environ["REDIS_PORT"])
    import socket

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5)
        s.connect((host, port))
        cmd = "*%d\r\n" % len(parts)
        for part in parts:
            p = str(part).encode("utf-8")
            cmd += "$%d\r\n%s\r\n" % (len(p), p.decode("utf-8"))
        s.sendall(cmd.encode("utf-8"))
        response = s.recv(4096)
        s.close()
        return response.decode("utf-8")
    except Exception as e:
        log("Redis connection error: %s" % e)
        return None


def wait_for_redis():
    max_retries = 30
    for i in range(max_retries):
        resp = redis_request(["PING"])
        if resp and "+PONG" in resp:
            log("connected to Redis")
            return True
        log("waiting for Redis... (%d/%d)" % (i + 1, max_retries))
        time.sleep(2)
    sys.exit(1)


def redis_set_device_token(device_name, token):
    resp = redis_request(["HSET", "device_tokens", device_name, token])
    if resp:
        log("stored token for device %s in Redis hash map 'device_tokens'" % device_name)
    else:
        log("failed to store token for device %s" % device_name)


def get_admin_credentials():
    username = os.environ.get("DEMO_ADMIN_USERNAME", "").strip()
    password = os.environ.get("DEMO_ADMIN_PASSWORD", "").strip()
    return username, password


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


def tb_request(method, path, payload=None, auth_headers=None):
    import urllib.parse
    base_url = os.environ["DEMO_THINGSBOARD_URL"]
    url = "%s%s" % (base_url, path)
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    if auth_headers:
        headers.update(auth_headers)
    data = json.dumps(payload).encode("utf-8") if payload else None
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request) as response:
            return json.loads(response.read().decode("utf-8")) if response.status != 204 else None
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8")
        log("ThingsBoard API error %d on %s %s: %s" % (e.code, method, path, body))
        raise
    except Exception as e:
        log("ThingsBoard connection error on %s %s: %s" % (method, path, e))
        raise


def ensure_demo_device_token(auth_headers, device_name):
    device_type = os.environ["DEMO_DEVICE_TYPE"]

    if auth_headers:
        log("ensuring demo device %s exists via ThingsBoard API" % device_name)
        import urllib.parse
        encoded_name = urllib.parse.quote(device_name, safe="")
        try:
            device = tb_request("GET", "/api/tenant/devices?deviceName=%s" % encoded_name, auth_headers=auth_headers)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                device = None
            else:
                raise
        if device is None:
            device = tb_request(
                "POST",
                "/api/device",
                {"name": device_name, "type": device_type},
                auth_headers=auth_headers,
            )
            log("created demo device %s" % device_name)
        else:
            log("reusing existing demo device %s" % device_name)

        device_id = device["id"]["id"]
        credentials = tb_request(
            "GET", "/api/device/%s/credentials" % device_id, auth_headers=auth_headers
        )
        return credentials["credentialsId"], device_id
    else:
        return os.environ["DEMO_DEVICE_TOKEN"], None


def cleanup_legacy_alarm_rules(auth_headers, device_profile_id):
    profile = tb_request("GET", "/api/deviceProfile/%s" % device_profile_id, auth_headers=auth_headers)
    alarms = profile.get("profileData", {}).get("alarms", [])
    if alarms:
        profile["profileData"]["alarms"] = []
        tb_request("POST", "/api/deviceProfile", payload=profile, auth_headers=auth_headers)
        log("cleaned up %d legacy alarm rule(s) from device profile" % len(alarms))


def provision_alarm_rules(auth_headers, device_profile_id):
    # Check if rule already exists (Calculated Fields API)
    existing = tb_request(
        "GET", 
        "/api/DEVICE_PROFILE/%s/calculatedFields?pageSize=100&page=0&sortProperty=createdTime&sortOrder=DESC&type=ALARM" % device_profile_id, 
        auth_headers=auth_headers
    )
    for rule in existing.get("data", []):
        if rule.get("name") == "high_anomaly_score":
            log("alarm rule 'high_anomaly_score' already exists, skipping")
            return

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
                    "alarmDetails": None,
                    "dashboardId": None
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
                "alarmDetails": None,
                "dashboardId": None
            },
            "propagate": False,
            "propagateToOwner": False,
            "propagateToTenant": False,
            "propagateRelationTypes": None,
            "output": None
        }
    }
    tb_request("POST", "/api/calculatedField", payload=alarm_payload, auth_headers=auth_headers)
    log("provisioned alarm rule 'high_anomaly_score' on device profile (Actual system)")


def provision_dashboard(auth_headers):
    dashboard_path = "/demo/dashboard.json"
    if not os.path.exists(dashboard_path):
        log("no dashboard.json found at %s, skipping dashboard provisioning" % dashboard_path)
        return

    try:
        with open(dashboard_path, "r") as f:
            dashboard_data = json.load(f)
    except Exception as e:
        log("failed to load dashboard.json: %s" % e)
        return

    existing = tb_request("GET", "/api/tenant/dashboards?pageSize=100&page=0", auth_headers=auth_headers)
    for d in existing.get("data", []):
        if d.get("title") == dashboard_data.get("title"):
            log("dashboard '%s' already exists, skipping" % dashboard_data.get("title"))
            return

    try:
        tb_request("POST", "/api/dashboard", payload=dashboard_data, auth_headers=auth_headers)
        log("provisioned dashboard '%s'" % dashboard_data.get("title"))
    except Exception as e:
        log("failed to provision dashboard: %s" % e)


def main():
    wait_for_redis()
    auth_headers = tb_auth()
    base_device_name = os.environ["DEMO_DEVICE_NAME"]
    alarm_rules_enabled = os.environ.get("DEMO_ALARM_RULES_ENABLED", "").lower() in ("true", "1", "yes")

    profile_id = None

    for i in range(1, 4):
        device_name = "%s-%d" % (base_device_name, i)
        device_token, device_id = ensure_demo_device_token(auth_headers, device_name)
        if device_token:
            redis_set_device_token(device_name, device_token)

        if alarm_rules_enabled and auth_headers and device_id and not profile_id:
            device = tb_request("GET", "/api/device/%s" % device_id, auth_headers=auth_headers)
            profile_id = device["deviceProfileId"]["id"]
            cleanup_legacy_alarm_rules(auth_headers, profile_id)
            provision_alarm_rules(auth_headers, profile_id)

    if auth_headers:
        provision_dashboard(auth_headers)

    return 0


if __name__ == "__main__":
    sys.exit(main())
