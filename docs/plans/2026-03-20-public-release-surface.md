# Public Release Surface Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add GitHub Actions workflows so this public repo publishes the `coprocessor` Helm chart to GHCR and syncs the public `rtbot-redis` image from private GAR to GHCR.

**Architecture:** Keep this repository as the public release surface only. The chart workflow packages and pushes the chart already stored in this repo, while the image workflow authenticates to GAR, pulls a caller-specified private image reference, retags it as `ghcr.io/rtbot-dev/rtbot-redis:<public_version>`, and pushes it to GHCR without rebuilding.

**Tech Stack:** GitHub Actions, Helm OCI support, Docker CLI, Google GitHub Actions auth, GHCR

---

### Task 1: Add chart publication workflow

**Files:**
- Create: `.github/workflows/publish-coprocessor-chart.yaml`
- Check: `Chart.yaml`

**Step 1:** Add a workflow triggered by tag push `coprocessor-chart-v*` and `workflow_dispatch`.

**Step 2:** Add steps to install Helm, log in to GHCR, package the root chart, and push it to `oci://ghcr.io/<owner>/helm-charts`.

**Step 3:** Add a verification step that pulls back `oci://ghcr.io/<owner>/helm-charts/coprocessor` for the packaged version.

### Task 2: Add image sync workflow

**Files:**
- Create: `.github/workflows/publish-rtbot-redis.yaml`

**Step 1:** Add a `workflow_dispatch` workflow with required inputs `source_image_ref` and `public_version`.

**Step 2:** Authenticate to Google Cloud with GitHub Actions, derive the GAR host from `source_image_ref`, and configure Docker for GAR access.

**Step 3:** Log in to GHCR with `GITHUB_TOKEN`, pull the private image, tag it as `ghcr.io/rtbot-dev/rtbot-redis:<public_version>`, and push it without rebuilding.

### Task 3: Update public release documentation

**Files:**
- Modify: `README.md`

**Step 1:** Add a minimal note near the top that this repo is the public release surface for the Helm chart and `rtbot-redis` image.

**Step 2:** Keep docs aligned to `rtbot-dev` while allowing the chart workflow to derive the package owner dynamically.

### Task 4: Verify repository state

**Files:**
- Check: `.github/workflows/publish-coprocessor-chart.yaml`
- Check: `.github/workflows/publish-rtbot-redis.yaml`
- Check: `README.md`

**Step 1:** Review the new workflow YAML for trigger, auth, packaging, push, and pull-back logic.

**Step 2:** Run a lightweight validation command if available and inspect `git diff` for correctness.
