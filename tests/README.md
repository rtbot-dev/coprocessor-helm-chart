# Coprocessor chart install smoke test

`install-smoke.sh` is a local-cluster harness for issue #480.

It validates the narrow install path that matters for this chart change:

- `helm` and `kubectl` are present
- a local `kind` or `minikube` context is actually reachable
- the chart can install into a fresh namespace without a PVC requirement
- the same-namespace ThingsBoard naming assumption is satisfied by a `thingsboard` Service in that namespace
- the release reaches a basic ready state and emits useful cluster diagnostics

It does not claim to validate real ThingsBoard behavior. The harness creates only a lightweight `thingsboard` Service stub so the chart can be exercised beside the same-namespace service assumption documented in `README.md`.

Run it from the repository root or anywhere else:

```bash
charts/coprocessor/tests/install-smoke.sh
```

Useful environment overrides:

- `KUBECTL_CONTEXT`: force a specific local context
- `ALLOW_NONLOCAL_CONTEXT=1`: intentionally allow a reachable non-local context; use with care because the harness creates and deletes namespaces
- `RELEASE_NAME`: override the Helm release name
- `NAMESPACE`: override the test namespace
- `TIMEOUT`: override the Helm and kubectl wait timeout, default `5m`
- `KEEP_NAMESPACE=1`: keep the namespace and release for manual inspection

Exit codes:

- `0`: install smoke passed
- `2`: skipped because required local tooling or a usable local cluster was not available
- other non-zero: the harness ran and found an install problem

## Not yet covered from #480

This harness is only the first install check. It does not yet validate:

- free-tier versus licensed behavior
- upgrade behavior
- uninstall/reinstall behavior
- broader values override scenarios
- prerequisite discovery beyond the basic local-runtime/tooling check
