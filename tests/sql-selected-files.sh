#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT_DIR/files/sql-runner/run.sh"

make_fake_redis() {
  local bin_dir="$1"
  local log_file="$2"

  mkdir -p "$bin_dir"
  cat > "$bin_dir/redis-cli" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log_file="${FAKE_REDIS_LOG:?}"
printf '%s\n' "$*" >> "$log_file"

if [ "${5:-}" = "PING" ]; then
  printf 'PONG\n'
  exit 0
fi

if [ "${5:-}" = "RTBOT.INFO" ]; then
  printf '{}\n'
  exit 0
fi

if [ "${5:-}" = "RTBOT.SQL" ]; then
  printf 'OK\n'
  exit 0
fi

printf 'unexpected redis-cli args: %s\n' "$*" >&2
exit 1
EOF
  chmod +x "$bin_dir/redis-cli"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"

  if ! printf '%s' "$haystack" | grep -Fq "$needle"; then
    printf 'expected to find %s in output\n' "$needle" >&2
    exit 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"

  if printf '%s' "$haystack" | grep -Fq "$needle"; then
    printf 'did not expect to find %s in output\n' "$needle" >&2
    exit 1
  fi
}

run_success_case() {
  local work_dir
  local sql_dir
  local bin_dir
  local log_file
  local output_file
  local sql_calls

  work_dir="$(mktemp -d)"
  sql_dir="$work_dir/sql"
  bin_dir="$work_dir/bin"
  log_file="$work_dir/redis.log"
  output_file="$work_dir/output.log"
  mkdir -p "$sql_dir"

  cat > "$sql_dir/01-first.sql" <<'EOF'
CREATE STREAM first_stream (value DOUBLE PRECISION);
EOF
  cat > "$sql_dir/02-second.sql" <<'EOF'
CREATE STREAM second_stream (value DOUBLE PRECISION);
EOF
  cat > "$sql_dir/notes.txt" <<'EOF'
ignore me
EOF

  make_fake_redis "$bin_dir" "$log_file"

  PATH="$bin_dir:$PATH" \
  FAKE_REDIS_LOG="$log_file" \
  REDIS_HOST="fake-host" \
  REDIS_PORT="6380" \
  SQL_DIR="$sql_dir" \
  SQL_SELECTED_FILES=$'02-second.sql\n01-first.sql' \
  bash "$RUNNER" > "$output_file" 2>&1

  sql_calls="$(grep 'RTBOT.SQL' "$log_file")"
  assert_contains "$sql_calls" 'RTBOT.SQL CREATE STREAM second_stream (value DOUBLE PRECISION)'
  assert_contains "$sql_calls" 'RTBOT.SQL CREATE STREAM first_stream (value DOUBLE PRECISION)'
  assert_not_contains "$sql_calls" 'notes.txt'

  if [ "$(printf '%s\n' "$sql_calls" | sed -n '1p')" != '-h fake-host -p 6380 RTBOT.SQL CREATE STREAM second_stream (value DOUBLE PRECISION)' ]; then
    printf 'expected second_stream to run first\n' >&2
    exit 1
  fi

  if [ "$(printf '%s\n' "$sql_calls" | sed -n '2p')" != '-h fake-host -p 6380 RTBOT.SQL CREATE STREAM first_stream (value DOUBLE PRECISION)' ]; then
    printf 'expected first_stream to run second\n' >&2
    exit 1
  fi
}

run_missing_file_case() {
  local work_dir
  local sql_dir
  local bin_dir
  local log_file
  local output_file

  work_dir="$(mktemp -d)"
  sql_dir="$work_dir/sql"
  bin_dir="$work_dir/bin"
  log_file="$work_dir/redis.log"
  output_file="$work_dir/output.log"
  mkdir -p "$sql_dir"

  cat > "$sql_dir/01-first.sql" <<'EOF'
CREATE STREAM first_stream (value DOUBLE PRECISION);
EOF

  make_fake_redis "$bin_dir" "$log_file"

  set +e
  PATH="$bin_dir:$PATH" \
  FAKE_REDIS_LOG="$log_file" \
  SQL_DIR="$sql_dir" \
  SQL_SELECTED_FILES=$'missing.sql' \
  bash "$RUNNER" > "$output_file" 2>&1
  status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    printf 'expected missing file case to fail\n' >&2
    exit 1
  fi

  assert_contains "$(cat "$output_file")" 'ERROR: Selected SQL file not found'
}

run_non_sql_case() {
  local work_dir
  local sql_dir
  local bin_dir
  local log_file
  local output_file

  work_dir="$(mktemp -d)"
  sql_dir="$work_dir/sql"
  bin_dir="$work_dir/bin"
  log_file="$work_dir/redis.log"
  output_file="$work_dir/output.log"
  mkdir -p "$sql_dir"

  cat > "$sql_dir/not-sql.txt" <<'EOF'
not sql
EOF

  make_fake_redis "$bin_dir" "$log_file"

  set +e
  PATH="$bin_dir:$PATH" \
  FAKE_REDIS_LOG="$log_file" \
  SQL_DIR="$sql_dir" \
  SQL_SELECTED_FILES=$'not-sql.txt' \
  bash "$RUNNER" > "$output_file" 2>&1
  status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    printf 'expected non-sql case to fail\n' >&2
    exit 1
  fi

  assert_contains "$(cat "$output_file")" 'ERROR: Selected SQL file must end with .sql'
}

run_success_case
run_missing_file_case
run_non_sql_case

printf 'sql selected files tests passed\n'
