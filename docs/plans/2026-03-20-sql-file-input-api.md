# SQL File Input API

Goal: let users provide RTBot SQL as files in the simplest possible way while still supporting shared pre-created ConfigMaps.

Decision:
- keep `sql.files` as the simple path for `--set-file`
- add `sql.selectedFiles` so users can explicitly choose which `.sql` files from an existing ConfigMap should run

User-facing model:
- simple: `helm install ... --set-file sql.files.pipeline.sql=./pipeline.sql`
- advanced: mount an existing ConfigMap and set `sql.selectedFiles` to the subset that should be executed

Execution rule:
- if `sql.selectedFiles` is empty, run all `*.sql` files in lexical order
- if `sql.selectedFiles` is set, run only those files, in listed order
