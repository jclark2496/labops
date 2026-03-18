#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

CMD="${1:-check}"

case "$CMD" in
  check)
    git fetch origin main --quiet 2>/dev/null || true
    LOCAL_HASH=$(git rev-parse HEAD)
    REMOTE_HASH=$(git rev-parse origin/main 2>/dev/null || echo "$LOCAL_HASH")
    LOCAL_VER=$(python3 -c "import json; print(json.load(open('version.json'))['version'])" 2>/dev/null || echo "0.0.0")
    REMOTE_VER=$(git show origin/main:version.json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['version'])" 2>/dev/null || echo "$LOCAL_VER")
    REMOTE_DATE=$(git show origin/main:version.json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('date',''))" 2>/dev/null || echo "")
    # Build changelog as JSON array
    REMOTE_CHANGELOG=$(git show origin/main:version.json 2>/dev/null | python3 -c "import sys,json; cl=json.load(sys.stdin).get('changelog',[]); print(json.dumps(cl))" 2>/dev/null || echo "[]")
    UPDATE_AVAILABLE="false"
    if [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then UPDATE_AVAILABLE="true"; fi
    # Check if rollback is available
    ROLLBACK="false"
    if [ -f "$REPO_DIR/.update-rollback-hash" ]; then ROLLBACK="true"; fi
    python3 -c "
import json
print(json.dumps({
    'localVersion': '$LOCAL_VER',
    'remoteVersion': '$REMOTE_VER',
    'remoteDate': '$REMOTE_DATE',
    'updateAvailable': $UPDATE_AVAILABLE,
    'localHash': '${LOCAL_HASH:0:8}',
    'remoteHash': '${REMOTE_HASH:0:8}',
    'changelog': json.loads('$REMOTE_CHANGELOG'),
    'rollbackAvailable': $ROLLBACK
}, indent=None))
" 2>/dev/null || echo '{"error":"check failed"}'
    ;;
  apply)
    git rev-parse HEAD > "$REPO_DIR/.update-rollback-hash"
    cp version.json "$REPO_DIR/.update-rollback-version.json" 2>/dev/null || true
    git pull origin main --ff-only 2>&1
    docker compose up -d 2>&1 || true
    echo '{"status":"ok","message":"Update applied successfully"}'
    ;;
  rollback)
    if [ ! -f "$REPO_DIR/.update-rollback-hash" ]; then
      echo '{"status":"error","message":"No rollback point available"}'
      exit 0
    fi
    ROLLBACK_HASH=$(cat "$REPO_DIR/.update-rollback-hash")
    git checkout "$ROLLBACK_HASH" -- . 2>&1
    docker compose up -d 2>&1 || true
    rm -f "$REPO_DIR/.update-rollback-hash" "$REPO_DIR/.update-rollback-version.json"
    echo '{"status":"ok","message":"Rolled back successfully"}'
    ;;
  *)
    echo '{"status":"error","message":"Unknown command. Use: check, apply, rollback"}'
    ;;
esac
