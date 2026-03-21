#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT_DIR/files/sql-runner/run.sh"

work_dir="$(mktemp -d)"
sql_dir="$work_dir/sql"
bin_dir="$work_dir/bin"
output_file="$work_dir/output.log"

mkdir -p "$sql_dir" "$bin_dir"

cat > "$sql_dir/01-first.sql" <<'EOF'
CREATE STREAM first_stream (value DOUBLE PRECISION);
EOF

cat > "$bin_dir/redis-cli" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${5:-}" = "PING" ]; then
  printf 'PONG\n'
  exit 0
fi

if [ "${5:-}" = "RTBOT.INFO" ]; then
  printf '{}\n'
  exit 0
fi

if [ "${5:-}" = "RTBOT.SQL" ]; then
  printf 'ERR unknown command %s\n' "${6:-}"
  exit 0
fi

exit 1
EOF

chmod +x "$bin_dir/redis-cli"

set +e
PATH="$bin_dir:$PATH" \
SQL_DIR="$sql_dir" \
bash "$RUNNER" > "$output_file" 2>&1
rc=$?
set -e

if [ "$rc" -eq 0 ]; then
  echo "expected runner to fail on Redis ERR response" >&2
  exit 1
fi

grep -q 'ERROR: Redis error:' "$output_file"

echo 'sql runner redis error test passed'
