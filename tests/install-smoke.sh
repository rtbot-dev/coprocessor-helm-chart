#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CHART_DIR=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)

RELEASE_NAME=${RELEASE_NAME:-coprocessor-smoke}
NAMESPACE=${NAMESPACE:-coprocessor-smoke}
TIMEOUT=${TIMEOUT:-5m}
KEEP_NAMESPACE=${KEEP_NAMESPACE:-0}
KUBECTL_CONTEXT=${KUBECTL_CONTEXT:-}
ALLOW_NONLOCAL_CONTEXT=${ALLOW_NONLOCAL_CONTEXT:-0}
SKIP_STATUS=2

STATEFULSET_NAME="${RELEASE_NAME}-coprocessor"
JOB_NAME="${STATEFULSET_NAME}-sql-bootstrap"
SELECTOR="app.kubernetes.io/instance=${RELEASE_NAME}"

LOG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/coprocessor-smoke.XXXXXX")
VALUES_FILE="${LOG_DIR}/values-smoke.yaml"

cleanup() {
  local exit_code
  exit_code=$?

  if [[ ${exit_code} -ne 0 && -n ${KUBECTL_CONTEXT} ]]; then
    dump_debug_state || true
  fi

  if [[ -n ${KUBECTL_CONTEXT} && ${KEEP_NAMESPACE} != "1" ]]; then
    kubectl --context "${KUBECTL_CONTEXT}" delete namespace "${NAMESPACE}" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
  fi

  printf 'Logs kept in %s\n' "${LOG_DIR}"
}

trap cleanup EXIT

log() {
  printf '==> %s\n' "$*"
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

fail() {
  local message status
  message=$1
  status=${2:-1}
  printf 'ERROR: %s\n' "${message}" >&2
  exit "${status}"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

dump_debug_state() {
  if ! kubectl --context "${KUBECTL_CONTEXT}" get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    return 0
  fi

  log "Collecting debug state from ${NAMESPACE}"
  kubectl --context "${KUBECTL_CONTEXT}" get all,configmap,secret,pvc -n "${NAMESPACE}" -o wide || true
  kubectl --context "${KUBECTL_CONTEXT}" get events -n "${NAMESPACE}" --sort-by=.metadata.creationTimestamp || true
  kubectl --context "${KUBECTL_CONTEXT}" describe statefulset "${STATEFULSET_NAME}" -n "${NAMESPACE}" || true

  local pod_names
  pod_names=$(kubectl --context "${KUBECTL_CONTEXT}" get pods -n "${NAMESPACE}" -l "${SELECTOR}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' || true)
  if [[ -n ${pod_names} ]]; then
    while IFS= read -r pod_name; do
      [[ -z ${pod_name} ]] && continue
      kubectl --context "${KUBECTL_CONTEXT}" describe pod "${pod_name}" -n "${NAMESPACE}" || true
      kubectl --context "${KUBECTL_CONTEXT}" logs "${pod_name}" -n "${NAMESPACE}" -c rtbot-redis --tail=200 || true
      kubectl --context "${KUBECTL_CONTEXT}" logs "${pod_name}" -n "${NAMESPACE}" -c connect --tail=200 || true
    done <<< "${pod_names}"
  fi

  kubectl --context "${KUBECTL_CONTEXT}" describe job "${JOB_NAME}" -n "${NAMESPACE}" || true
  kubectl --context "${KUBECTL_CONTEXT}" logs job/"${JOB_NAME}" -n "${NAMESPACE}" --tail=200 || true
  helm status "${RELEASE_NAME}" -n "${NAMESPACE}" || true
}

select_context() {
  local current_context kind_cluster

  if [[ -n ${KUBECTL_CONTEXT} ]]; then
    if kubectl --context "${KUBECTL_CONTEXT}" cluster-info >/dev/null 2>&1; then
      if [[ ${ALLOW_NONLOCAL_CONTEXT} != "1" ]]; then
        case "${KUBECTL_CONTEXT}" in
          kind-*|minikube)
            ;;
          *)
            fail "KUBECTL_CONTEXT '${KUBECTL_CONTEXT}' is reachable but not a local kind/minikube context. Set ALLOW_NONLOCAL_CONTEXT=1 to use it intentionally." "${SKIP_STATUS}"
            ;;
        esac
      fi
      return 0
    fi
    fail "Requested KUBECTL_CONTEXT '${KUBECTL_CONTEXT}' is not reachable." "${SKIP_STATUS}"
  fi

  current_context=$(kubectl config current-context 2>/dev/null || true)
  if [[ -n ${current_context} ]] && kubectl --context "${current_context}" cluster-info >/dev/null 2>&1; then
    case "${current_context}" in
      kind-*|minikube)
        KUBECTL_CONTEXT=${current_context}
        return 0
        ;;
    esac
  fi

  if have_cmd kind; then
    kind_cluster=$(kind get clusters 2>/dev/null | head -n 1 || true)
    if [[ -n ${kind_cluster} ]] && kubectl --context "kind-${kind_cluster}" cluster-info >/dev/null 2>&1; then
      KUBECTL_CONTEXT="kind-${kind_cluster}"
      return 0
    fi
  fi

  if have_cmd minikube && minikube status >/dev/null 2>&1 && kubectl --context minikube cluster-info >/dev/null 2>&1; then
    KUBECTL_CONTEXT=minikube
    return 0
  fi

  fail "No usable local kind or minikube cluster is available. Start one, or set KUBECTL_CONTEXT to a reachable local context." "${SKIP_STATUS}"
}

for required_tool in kubectl helm; do
  have_cmd "${required_tool}" || fail "Missing required tool '${required_tool}'." "${SKIP_STATUS}"
done

if ! have_cmd kind && ! have_cmd minikube; then
  fail "Neither kind nor minikube is installed. Install one local runtime and retry." "${SKIP_STATUS}"
fi

select_context

cat > "${VALUES_FILE}" <<'EOF'
persistence:
  enabled: false

sql:
  bootstrapJob:
    hook: false
  files:
    01-smoke.sql: |
      CREATE STREAM sensors (device_id DOUBLE PRECISION, temperature DOUBLE PRECISION);

      CREATE MATERIALIZED VIEW temp_avg AS
        SELECT device_id,
               MOVING_AVERAGE(temperature, 5) AS avg_temp
        FROM sensors
        GROUP BY device_id;

connect:
  egress:
    enabled: false
EOF

log "Using kubectl context ${KUBECTL_CONTEXT}"
helm version --short
kubectl version --client=true
kubectl --context "${KUBECTL_CONTEXT}" get nodes -o wide

log "Preparing namespace ${NAMESPACE}"
kubectl --context "${KUBECTL_CONTEXT}" create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl --context "${KUBECTL_CONTEXT}" apply -f -

log "Creating same-namespace ThingsBoard service stub"
cat <<EOF | kubectl --context "${KUBECTL_CONTEXT}" apply -f -
apiVersion: v1
kind: Service
metadata:
  name: thingsboard
  namespace: ${NAMESPACE}
spec:
  ports:
    - name: http
      port: 8080
      targetPort: 8080
EOF

kubectl --context "${KUBECTL_CONTEXT}" get service thingsboard -n "${NAMESPACE}" -o wide

log "Installing chart ${CHART_DIR} as release ${RELEASE_NAME}"
helm install "${RELEASE_NAME}" "${CHART_DIR}" \
  --namespace "${NAMESPACE}" \
  --values "${VALUES_FILE}" \
  --wait \
  --wait-for-jobs \
  --timeout "${TIMEOUT}" | tee "${LOG_DIR}/helm-install.log"

log "Verifying release resources"
kubectl --context "${KUBECTL_CONTEXT}" rollout status statefulset/"${STATEFULSET_NAME}" -n "${NAMESPACE}" --timeout="${TIMEOUT}"
kubectl --context "${KUBECTL_CONTEXT}" wait --for=condition=complete job/"${JOB_NAME}" -n "${NAMESPACE}" --timeout="${TIMEOUT}"
kubectl --context "${KUBECTL_CONTEXT}" get service "${STATEFULSET_NAME}" -n "${NAMESPACE}" -o wide
kubectl --context "${KUBECTL_CONTEXT}" get all,configmap,secret,pvc -n "${NAMESPACE}" -l "${SELECTOR}" -o wide
kubectl --context "${KUBECTL_CONTEXT}" get events -n "${NAMESPACE}" --sort-by=.metadata.creationTimestamp
helm status "${RELEASE_NAME}" -n "${NAMESPACE}"

log "Install smoke passed"
