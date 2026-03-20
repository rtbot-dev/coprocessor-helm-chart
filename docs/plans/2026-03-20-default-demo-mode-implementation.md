# Default Demo Mode Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a default-on demo experience to the public coprocessor chart so a first install visibly shows telemetry entering ThingsBoard, being processed, and coming back as derived analytics.

**Architecture:** Extend the public chart with a `demo` values block, a deterministic demo SQL bundle, and one or more demo Kubernetes resources that either provision or use a demo device and continuously publish telemetry. Keep the demo easy to disable later and document that path clearly.

**Tech Stack:** Helm, Kubernetes YAML templates, existing chart bootstrap model, chart README/docs, shell-based validation where possible.

---

### Task 1: Add demo values and demo SQL bundle

**Files:**
- Modify: `values.yaml`
- Modify: `values-demo.yaml`
- Modify: `values.schema.json`
- Create: `files/demo/*.sql`

**Step 1: Write the failing check**

Run:

```bash
grep -R "^demo:" values.yaml values-demo.yaml
```

Expected: no demo block yet.

**Step 2: Add the demo values surface**

Include values for enable/disable, device identity, token/admin mode, publisher cadence, and demo SQL selection.

**Step 3: Add the demo SQL files**

Create a richer default bundle with heartbeat, moving average, trend/delta, and threshold flag examples.

**Step 4: Verify render compatibility**

Run:

```bash
helm lint .
helm template coprocessor .
```

Expected: pass.

### Task 2: Add demo runtime resources

**Files:**
- Create: `templates/demo-configmap.yaml`
- Create: `templates/demo-publisher.yaml`
- Create: `templates/demo-job.yaml` or equivalent bootstrap resource if needed
- Modify: `templates/sql-configmap.yaml`

**Step 1: Write the failing render check**

Run:

```bash
helm template coprocessor . | grep demo
```

Expected: no meaningful demo resources yet.

**Step 2: Add demo runtime resources**

Create the publisher/config resources needed for the default demo to emit telemetry continuously.

**Step 3: Verify render**

Run:

```bash
helm template coprocessor . > /tmp/coprocessor-demo-default.yaml
```

Expected: demo resources render by default.

### Task 3: Document the demo-first install flow

**Files:**
- Modify: `README.md`
- Modify: `templates/NOTES.txt`

**Step 1: Write the failing doc check**

Review the current README and confirm it does not yet explain a default-on demo experience.

**Step 2: Update docs**

Document:

- what the default demo does
- what values are required to make it work
- how to disable it for more professional/production use

**Step 3: Verify docs and chart still lint**

Run:

```bash
helm lint .
```

Expected: pass.
