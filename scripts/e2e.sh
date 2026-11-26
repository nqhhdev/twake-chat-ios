#!/usr/bin/env bash
# End-to-end tests (XCUITest, test plan E2E) against a real Synapse.
#
#   scripts/e2e.sh up       boot Synapse, check sliding sync, register the test users and seed the rooms.
#                           Uses twake-space-chat/e2e when that repo is checked out, otherwise e2e/ in this repo.
#   scripts/e2e.sh test     run the E2E test plan on the simulator ($SIMULATOR_NAME, default "iPhone 16e")
#   scripts/e2e.sh down     stop the stack and remove its volumes
#   scripts/e2e.sh all      up, test, down (down runs even when a test fails)
#   scripts/e2e.sh staging  run the E2E plan against staging (ADR 0020), credentials from
#                           ~/.factos/secrets/twake-chat-ios-staging.env (never printed)
#   scripts/e2e.sh cold-start  run ColdStartFlowTests and push its notification with `simctl push` while the app is
#                           killed (issue #84); needs `up` first
#
# Environment: WEB_E2E (path of twake-space-chat/e2e), SIMULATOR_NAME, E2E_HOMESERVER (skip `up`, use this server).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD

# Prefer the web e2e stack when it is checked out; otherwise the bundled Synapse in this repo (CI).
if [ -z "${WEB_E2E:-}" ]; then
  if [ -d "$HOME/Documents/Linagora/twake-space-chat/e2e/docker" ]; then
    WEB_E2E="$HOME/Documents/Linagora/twake-space-chat/e2e"
  else
    WEB_E2E="$ROOT/e2e"
  fi
fi
COMPOSE=(docker compose -p twake-ios-e2e -f "$WEB_E2E/docker/docker-compose.yaml")
SYNAPSE_IMAGE=ghcr.io/element-hq/synapse:v1.162.0
HS="${E2E_HOMESERVER:-http://localhost:8008}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 16e}"
RESULTS="${RESULTS:-$ROOT/build/e2e}"
PASSWORD=password

log() { printf '\033[1m[e2e]\033[0m %s\n' "$*"; }
die() { printf '[e2e] error: %s\n' "$*" >&2; exit 1; }

login_token() { # user password -> access token
  curl -fsS -X POST "$HS/_matrix/client/v3/login" -H 'Content-Type: application/json' \
    -d "{\"type\":\"m.login.password\",\"identifier\":{\"type\":\"m.id.user\",\"user\":\"$1\"},\"password\":\"$2\"}" |
    sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'
}

api() { # token method path [json]
  curl -fsS -X "$2" "$HS/_matrix/client/v3$3" -H "Authorization: Bearer $1" \
    -H 'Content-Type: application/json' ${4:+-d "$4"}
}

check_server() {
  log "checking $HS"
  local versions
  versions=$(curl -fsS "$HS/_matrix/client/versions") || die "no Matrix server at $HS"
  grep -q '"org.matrix.simplified_msc3575":true' <<<"$versions" ||
    die "$HS does not announce sliding sync (org.matrix.simplified_msc3575); use 'scripts/e2e.sh staging' (ADR 0020)"
  log "sliding sync: ok"
  # ToM is optional for the flows of this suite; contacts and recovery words need it.
  if curl -fsS -o /dev/null "${E2E_TOM:-http://localhost:3001}/_matrix/identity/v2" 2>/dev/null; then
    log "ToM: ok"
  else
    log "ToM: not running (flows that need /_twake are skipped)"
  fi
}

up() {
  docker info >/dev/null 2>&1 || die "Docker is not running (open -a Docker, or use the CI Colima setup)"
  [ -f "$WEB_E2E/docker/docker-compose.yaml" ] || die "e2e compose not found at $WEB_E2E/docker (set WEB_E2E)"
  export E2E_UID="$(id -u)" E2E_GID="$(id -g)"
  if [ -d "$WEB_E2E/docker/synapse" ]; then
    # Only this stack reads a host data folder. The bundled stack ships its key and log config, and
    # Colima mounts the home folder read-only, so `generate` into a host bind fails there.
    local data="$WEB_E2E/.data/synapse"
    if [ ! -f "$data/localhost.signing.key" ]; then
      mkdir -p "$data"
      docker run --rm -v "$data:/data" -e UID="$E2E_UID" -e GID="$E2E_GID" \
        -e SYNAPSE_SERVER_NAME=localhost -e SYNAPSE_REPORT_STATS=no "$SYNAPSE_IMAGE" generate >/dev/null
    fi
    if [ ! -f "$data/tls.crt" ]; then
      openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=localhost" \
        -addext "subjectAltName=DNS:localhost" -keyout "$data/tls.key" -out "$data/tls.crt" >/dev/null 2>&1
      chmod 644 "$data/tls.key"
    fi
    cp "$WEB_E2E/docker/synapse/homeserver.yaml" "$data/"
    for extra in side-service.yaml harness.yaml; do
      [ -f "$WEB_E2E/docker/synapse/$extra" ] && cp "$WEB_E2E/docker/synapse/$extra" "$data/"
    done
    # No OIDC provider: the app then takes its password route (ADR 0021), so XCUITest signs in
    # without the system web-authentication sheet.
    strip_oidc "$data/homeserver.yaml"
    log "starting Synapse (twake-space-chat stack at $WEB_E2E)"
    "${COMPOSE[@]}" up -d --wait postgres mailpit dex ldap synapse
  else
    # Named volume + read-only config mounts (e2e/docker/docker-compose.yaml): no host
    # bind of /data, so Colima cannot leave the store read-only.
    log "starting Synapse (bundled stack at $WEB_E2E)"
    "${COMPOSE[@]}" up -d --wait
  fi
  check_server
  seed
}

strip_oidc() { # drops the top-level oidc_providers block of a homeserver.yaml
  python3 - "$1" <<'PY'
import re, sys
path = sys.argv[1]
lines = open(path).read().splitlines(keepends=True)
out, skip = [], False
for line in lines:
    if re.match(r"^oidc_providers:", line):
        skip = True
        continue
    if skip and re.match(r"^[A-Za-z#]", line):
        skip = False
    if not skip:
        out.append(line)
open(path, "w").write("".join(out))
PY
}

register_admin() {
  for _ in $(seq 1 15); do
    "${COMPOSE[@]}" exec -T synapse register_new_matrix_user -u e2eadmin -p e2eadmin-password --admin \
      -c /data/homeserver.yaml http://localhost:8008 >/dev/null 2>&1 || true
    [ -n "$(login_token e2eadmin e2eadmin-password 2>/dev/null)" ] && return 0
    sleep 2
  done
  die "could not register the admin"
}

seed() {
  log "registering users"
  register_admin
  local admin
  admin=$(login_token e2eadmin e2eadmin-password)
  for user in ios-alice ios-bob; do
    curl -fsS -X PUT "$HS/_synapse/admin/v2/users/@$user:localhost" -H "Authorization: Bearer $admin" \
      -H 'Content-Type: application/json' \
      -d "{\"password\":\"$PASSWORD\",\"displayname\":\"${user#ios-} E2E\",\"admin\":false,\"logout_devices\":true}" >/dev/null
  done
  local alice bob
  alice=$(login_token ios-alice "$PASSWORD")
  bob=$(login_token ios-bob "$PASSWORD")
  # The profile name flow checks this exact name.
  api "$alice" PUT "/profile/@ios-alice:localhost/displayname" '{"displayname":"Alice E2E"}' >/dev/null
  log "seeding rooms"
  local chat history
  chat=$(seed_room "$alice" "E2E Chat")
  history=$(seed_room "$alice" "E2E History")
  for room in "$chat" "$history"; do
    api "$alice" POST "/rooms/$room/invite" '{"user_id":"@ios-bob:localhost"}' >/dev/null || true
    api "$bob" POST "/join/$room" '{}' >/dev/null
  done
  api "$bob" PUT "/rooms/$chat/send/m.room.message/seed-hello" '{"msgtype":"m.text","body":"Hello from Bob"}' >/dev/null
  # 300 messages, so the history needs several pages (TimelineProxy.pageSize is 30).
  if ! api "$alice" GET "/rooms/$history/messages?dir=b&limit=5" | grep -q '"History 300"'; then
    for i in $(seq 1 300); do
      api "$bob" PUT "/rooms/$history/send/m.room.message/seed-$i" \
        "{\"msgtype\":\"m.text\",\"body\":\"History $i\"}" >/dev/null
    done
  fi
  log "seeded: E2E Chat, E2E History (300 messages)"
}

seed_room() { # token name -> room id (reuses a joined room of that name)
  local token=$1 name=$2 rooms id
  rooms=$(api "$token" GET /joined_rooms | grep -o '![^"]*' || true)
  for id in $rooms; do
    if api "$token" GET "/rooms/$id/state/m.room.name" 2>/dev/null | grep -q "\"name\":\"$name\""; then
      echo "$id"; return
    fi
  done
  api "$token" POST /createRoom "{\"name\":\"$name\",\"preset\":\"private_chat\"}" |
    sed -n 's/.*"room_id":"\([^"]*\)".*/\1/p'
}

pick_simulator() {
  simulator_udid "$SIMULATOR_NAME" && return 0
  local name
  for name in "iPhone 17 Pro" "iPhone 17" "iPhone 16e" "iPhone 16" "iPhone 15"; do
    if simulator_udid "$name"; then
      SIMULATOR_NAME=$name
      return 0
    fi
  done
  name=$(xcrun simctl list devices available | sed -n 's/^ *\(iPhone [^()]*\) (\([0-9A-F-]\{36\}\)).*/\1/p' | head -1)
  [ -n "$name" ] || return 1
  SIMULATOR_NAME=$name
}

simulator_udid() { # name -> udid on stdout, or 1 if missing
  local udid
  udid=$(xcrun simctl list devices available | grep -F "    $1 (" | head -1 |
    sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
  [ -n "$udid" ] || return 1
  printf '%s\n' "$udid"
}

run_tests() { # homeserver user password
  local udid
  pick_simulator || die "no iPhone simulator available"
  udid=$(simulator_udid "$SIMULATOR_NAME") || die "no simulator named '$SIMULATOR_NAME'"
  rm -rf "$RESULTS.xcresult" "$RESULTS.log"
  mkdir -p "$(dirname "$RESULTS")"
  log "testing on $SIMULATOR_NAME ($udid)"
  # TEST_RUNNER_ variables reach the UI test runner without the prefix (ADR 0020); the tests hand E2E_HOMESERVER to
  # the app in its launch environment.
  local status=0
  TEST_RUNNER_E2E_HOMESERVER="$1" TEST_RUNNER_E2E_USER="$2" TEST_RUNNER_E2E_PASSWORD="$3" \
    TEST_RUNNER_E2E_PEER="${4:-}" \
    xcodebuild test -project TwakeChat.xcodeproj -scheme TwakeChat -testPlan E2E \
    -destination "platform=iOS Simulator,id=$udid" -resultBundlePath "$RESULTS.xcresult" \
    >"$RESULTS.log" 2>&1 || status=$?
  grep -E '(Test Case|error:|Expected failure|\*\* )' "$RESULTS.log" || true
  log "result bundle: $RESULTS.xcresult (exit $status)"
  return "$status"
}

down() {
  log "stopping the stack"
  "${COMPOSE[@]}" down -v
}

cold_start() {
  local udid token room event payload pid pushed status=0 alias="%23ios-cold-start:localhost"
  pick_simulator || die "no iPhone simulator available"
  udid=$(simulator_udid "$SIMULATOR_NAME") || die "no simulator named '$SIMULATOR_NAME'"
  mkdir -p "$(dirname "$RESULTS")"
  rm -rf "$RESULTS-cold-start.xcresult"
  log "cold start on $SIMULATOR_NAME ($udid)"
  TEST_RUNNER_E2E_HOMESERVER="$HS" TEST_RUNNER_E2E_USER=ios-alice TEST_RUNNER_E2E_PASSWORD="$PASSWORD" \
    TEST_RUNNER_E2E_PUSHES_COLD_START=1 \
    xcodebuild test -project TwakeChat.xcodeproj -scheme TwakeChat -testPlan E2E \
    -only-testing:"TwakeChatUITests/ColdStartFlowTests${COLD_START_TEST:+/$COLD_START_TEST}" -destination "platform=iOS Simulator,id=$udid" \
    -resultBundlePath "$RESULTS-cold-start.xcresult" >"$RESULTS-cold-start.log" 2>&1 &
  pid=$!
  token=$(login_token ios-alice "$PASSWORD")
  curl -fsS -X DELETE "$HS/_matrix/client/v3/directory/room/$alias" -H "Authorization: Bearer $token" >/dev/null 2>&1 || true
  pushed=" "
  while kill -0 "$pid" 2>/dev/null; do
    room=$(curl -fsS "$HS/_matrix/client/v3/directory/room/$alias" -H "Authorization: Bearer $token" 2>/dev/null |
      sed -n 's/.*"room_id":"\([^"]*\)".*/\1/p' || true)
    event=""
    if [ -n "$room" ]; then
      event=$(api "$token" GET "/rooms/$room/messages?dir=b&limit=5" 2>/dev/null |
        python3 -c 'import json,sys; print(next((e["event_id"] for e in json.load(sys.stdin)["chunk"] if e["type"]=="m.room.message" and "cold start ping" in e.get("content",{}).get("body","")),""))' || true)
    fi
    if [ -n "$event" ] && [ "${pushed#* $event }" = "$pushed" ]; then
      pushed="$pushed$event "
      sleep 3
      payload=$(mktemp)
      printf '{"Simulator Target Bundle":"app.twake.ios.chat","aps":{"alert":{"title":"Cold start","body":"cold start ping"},"mutable-content":1,"sound":"default"},"room_id":"%s","event_id":"%s"}' \
        "$room" "$event" >"$payload"
      log "pushing $event in $room"
      xcrun simctl push "$udid" app.twake.ios.chat "$payload"
      rm -f "$payload"
    fi
    sleep 1
  done
  wait "$pid" || status=$?
  api "$token" POST /logout '{}' >/dev/null 2>&1 || true
  grep -E '(Test Case|error:|\*\* )' "$RESULTS-cold-start.log" || true
  log "result bundle: $RESULTS-cold-start.xcresult (exit $status)"
  return "$status"
}

case "${1:-all}" in
  up) up ;;
  seed) seed ;;
  check) check_server ;;
  test) check_server && run_tests "$HS" ios-alice "$PASSWORD" "@ios-bob:localhost" ;;
  down) down ;;
  cold-start) check_server && cold_start ;;
  all)
    up
    status=0
    run_tests "$HS" ios-alice "$PASSWORD" "@ios-bob:localhost" || status=$?
    down
    exit "$status"
    ;;
  staging)
    env_file="$HOME/.factos/secrets/twake-chat-ios-staging.env"
    [ -f "$env_file" ] || die "no $env_file"
    set -a; . "$env_file"; set +a
    HS="$MATRIX_HOMESERVER" check_server
    run_tests "$MATRIX_HOMESERVER" "$MATRIX_USER" "$MATRIX_PASSWORD"
    ;;
  *) sed -n '2,13p' "$0"; exit 2 ;;
esac
