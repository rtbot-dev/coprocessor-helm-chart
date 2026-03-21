# Demo Experience — Implementation Plan

### Task 1: Update publisher.py
Modify `publisher.py` in `templates/demo-configmap.yaml`:
- Change `build_payload` to accept a `device_index` for phase offset and random anomaly injection (+25.0, 5% chance).
- Change `main()` loop to iterate over 3 devices (`{DEMO_DEVICE_NAME}-{1,2,3}`).

### Task 2: Update bootstrap.py
Modify `bootstrap.py` in `templates/demo-configmap.yaml`:
- Change `main()` to loop over the 3 devices, calling `ensure_demo_device_token` and `redis_set_device_token` for each.
- Add `provision_dashboard()` to read `/demo/dashboard.json` and `POST /api/dashboard`.

### Task 3: Add placeholder dashboard and update configmap
- Add an empty `dashboard.json` to `files/demo/dashboard.json`.
- Map it into `templates/demo-configmap.yaml` using `.Files.Get`.

### Task 4: Deploy and Build Dashboard
- Deploy the updated chart.
- Log into ThingsBoard (Playwright), verify devices and alarms.
- Create a visual dashboard in ThingsBoard UI, export the JSON, and overwrite `files/demo/dashboard.json` with the real layout.
- Re-deploy to verify auto-provisioning works.
