import json
import math
import os
import random
import sys
import time
import urllib.error
import urllib.request


def log(message):
    print("[demo-publisher] %s" % message, flush=True)


def build_payload(step, device_index):
    base = float(os.environ["DEMO_BASE_TEMPERATURE"])
    amplitude = float(os.environ["DEMO_TEMPERATURE_AMPLITUDE"])
    step_degrees = float(os.environ["DEMO_TEMPERATURE_STEP_DEGREES"])
    
    # 120 degree phase offset per device so they don't perfectly overlap
    radians = math.radians((step * step_degrees) + (device_index * 120))
    temperature = base + amplitude * math.sin(radians)

    # 5% chance of an anomaly per reading (spike +25 degrees)
    if random.random() < 0.05:
        temperature += 25.0
        log("injecting +25.0 degree anomaly for device index %d" % device_index)

    return {
        "temperature": round(temperature, 2),
        "heartbeat": 1,
    }


def publish(step, device_name, device_index):
    data = build_payload(step, device_index)
    payload = json.dumps(data).encode("utf-8")
    timestamp_ms = str(int(time.time() * 1000))
    request = urllib.request.Request(
        os.environ["DEMO_INGEST_URL"],
        data=payload,
        headers={
            "Content-Type": "application/json",
            os.environ["DEMO_DEVICE_HEADER"]: device_name,
            os.environ["DEMO_TIMESTAMP_HEADER"]: timestamp_ms,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            response.read()
            return response.status, data
    except urllib.error.HTTPError as e:
        return e.code, data
    except Exception as e:
        return 500, data


def main():
    interval_seconds = int(os.environ["DEMO_INTERVAL_SECONDS"])
    base_device_name = os.environ["DEMO_DEVICE_NAME"]
    step = 0
    while True:
        # Publish to 3 separate devices
        for i in range(1, 4):
            device_name = "%s-%d" % (base_device_name, i)
            status, data = publish(step, device_name, i)
            log("step %d, device %s -> %s (status %s)" % (step, device_name, data, status))
        step += 1
        time.sleep(interval_seconds)


if __name__ == "__main__":
    main()
