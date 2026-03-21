# Demo Experience — Design

## Objective
Make the coprocessor demo environment compelling for live presentations by adding multi-device support, anomaly injection to trigger alarms, and an auto-provisioned ThingsBoard dashboard.

## Multi-Device Setup
Instead of a single device, the system will use a fixed pool of 3 devices to prove the `GROUP BY device_id` capability of RTBot SQL.
- **Bootstrap script:** Loops 3 times to provision `coprocessor-demo-device-1`, `-2`, and `-3` in ThingsBoard. Stores all 3 tokens in Redis.
- **Publisher script:** Loops over the 3 devices in its main loop. Each device gets a 120-degree phase offset to its sine wave so the charts don't perfectly overlap.

## Anomaly Injection
To guarantee alarm rules fire during a demo, synthetic anomalies will be injected.
- **Publisher script:** Adds a 5% chance per device per tick to inject a "spike".
- An anomaly adds `+25.0` to the base temperature for one reading.
- This causes the `anomaly_score` to exceed the `10.0` threshold, triggering the `high_anomaly_score` alarm.

## Dashboard Auto-Provisioning
- **New file:** `files/demo/dashboard.json` will contain a pre-configured ThingsBoard dashboard layout.
- **Bootstrap script:** Reads the JSON and POSTs it to `/api/dashboard`. This makes the dashboard instantly accessible in the UI.

This requires no changes to the Helm values schema or RTBot SQL.
