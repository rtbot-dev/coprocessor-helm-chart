#!/usr/bin/env bash
#
# sql-runner: Idempotent init container script for Coprocessor.
# Reads *.sql files from SQL_DIR and executes RTBOT.SQL statements against rtbot-redis.
#
# Environment variables:
#   REDIS_HOST    - Redis host (default: localhost)
#   REDIS_PORT    - Redis port (default: 6379)
#   SQL_DIR       - Directory containing *.sql files (default: /sql)
#   MAX_RETRIES   - Max connection retries (default: 30)
#   RETRY_DELAY   - Seconds between retries (default: 2)

set -euo pipefail

REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
SQL_DIR="${SQL_DIR:-/sql}"
MAX_RETRIES="${MAX_RETRIES:-30}"
RETRY_DELAY="${RETRY_DELAY:-2}"

log() {
  echo "[sql-runner] $(date -u '+%Y-%m-%dT%H:%M:%SZ') $*"
}

redis_cmd() {
  redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" "$@"
}

wait_for_redis() {
  local attempt=1
  while [ "$attempt" -le "$MAX_RETRIES" ]; do
    if redis_cmd PING 2>/dev/null | grep -q PONG; then
      log "rtbot-redis is ready"
      return 0
    fi
    log "Waiting for rtbot-redis (attempt $attempt/$MAX_RETRIES)..."
    sleep "$RETRY_DELAY"
    attempt=$((attempt + 1))
  done
  log "ERROR: rtbot-redis not ready after $MAX_RETRIES attempts"
  return 1
}

get_deployed_pipelines() {
  redis_cmd RTBOT.INFO json 2>/dev/null || echo "{}"
}

is_view_deployed() {
  local view_name="$1"
  local pipeline_id="sql_mv_${view_name}"
  local info
  info=$(get_deployed_pipelines)

  if echo "$info" | grep -q "\"${pipeline_id}\""; then
    return 0
  fi
  return 1
}

extract_view_name() {
  local stmt="$1"
  echo "$stmt" | sed -n 's/.*[Cc][Rr][Ee][Aa][Tt][Ee][[:space:]]\{1,\}[Mm][Aa][Tt][Ee][Rr][Ii][Aa][Ll][Ii][Zz][Ee][Dd][[:space:]]\{1,\}[Vv][Ii][Ee][Ww][[:space:]]\{1,\}\([A-Za-z_][A-Za-z0-9_]*\).*/\1/p' | head -1
}

is_create_mv() {
  local stmt="$1"
  echo "$stmt" | grep -qi 'CREATE[[:space:]]\{1,\}MATERIALIZED[[:space:]]\{1,\}VIEW'
}

execute_statement() {
  local stmt="$1"
  local trimmed
  trimmed=$(echo "$stmt" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

  if [ -z "$trimmed" ]; then
    return 0
  fi

  if is_create_mv "$trimmed"; then
    local view_name
    view_name=$(extract_view_name "$trimmed")
    if [ -n "$view_name" ] && is_view_deployed "$view_name"; then
      log "Pipeline sql_mv_${view_name} already deployed, skipping"
      return 0
    fi
  fi

  log "Executing: ${trimmed:0:80}..."
  local result
  result=$(redis_cmd RTBOT.SQL "$trimmed" 2>&1)
  local exit_code=$?

  if [ $exit_code -ne 0 ]; then
    log "ERROR: Statement failed (exit=$exit_code): $result"
    return 1
  fi

  if echo "$result" | grep -q "^(error)"; then
    log "ERROR: Redis error: $result"
    return 1
  fi

  log "OK: $result"
  return 0
}

process_sql_file() {
  local file="$1"
  log "Processing: $file"

  local statement=""
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *--*) line=$(echo "$line" | sed 's/--.*//') ;;
    esac
    statement="${statement} ${line}"
    case "$line" in
      *\;*)
        statement=$(echo "$statement" | sed 's/;[[:space:]]*$//')
        execute_statement "$statement"
        statement=""
        ;;
    esac
  done < "$file"

  local remaining
  remaining=$(echo "$statement" | sed 's/[[:space:]]//g')
  if [ -n "$remaining" ]; then
    statement=$(echo "$statement" | sed 's/;[[:space:]]*$//')
    execute_statement "$statement"
  fi
}

main() {
  log "Starting sql-runner"
  log "Redis: ${REDIS_HOST}:${REDIS_PORT}"
  log "SQL directory: ${SQL_DIR}"

  wait_for_redis

  if [ ! -d "$SQL_DIR" ]; then
    log "WARNING: SQL directory $SQL_DIR does not exist, nothing to do"
    exit 0
  fi

  local found_files=0
  for file in "$SQL_DIR"/*.sql; do
    [ -e "$file" ] || continue
    found_files=1
    process_sql_file "$file"
  done

  if [ "$found_files" -eq 0 ]; then
    log "WARNING: No .sql files found in $SQL_DIR"
  fi

  log "sql-runner completed successfully"
  exit 0
}

main "$@"
