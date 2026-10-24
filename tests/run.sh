#!/usr/bin/env bash
# Tests for knock and install.sh.
#
# Needs bash and Python 3 (set PYTHON to choose the interpreter). nc is used
# for the nc sender test when present.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PY="${PYTHON:-python3}"
K="$ROOT/knock"
pass=0
fail=0
tmp=$(mktemp -d)
pids=()
cleanup() {
  for p in "${pids[@]}"; do
    kill "$p" 2>/dev/null
    { wait "$p"; } 2>/dev/null
  done
  rm -rf "$tmp"
}
trap cleanup EXIT

ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; }

# expect DESC WANT CMD...: WANT 0 means the command must succeed, 1 that it must fail.
expect() {
  local desc="$1" want="$2" out rc
  shift 2
  out=$("$@" 2>&1)
  rc=$?
  if { [ "$want" = 0 ] && [ "$rc" -eq 0 ]; } || { [ "$want" != 0 ] && [ "$rc" -ne 0 ]; }; then
    ok "$desc"
  else
    bad "$desc" "rc=$rc: $out"
  fi
}

# check DESC CONDITION-COMMAND...: passes when the command succeeds.
check() {
  local desc="$1"
  shift
  if "$@"; then ok "$desc"; else bad "$desc"; fi
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{ print $1 }'; else shasum -a 256 "$1" | awk '{ print $1 }'; fi
}

export KNOCK_SETTLE_MS=0 KNOCK_CONF=/nonexistent/knock.conf KNOCK_QUIET=1

echo "# knock arguments"
expect "packaged client form" 0 "$K" -u -d 20 127.0.0.1 40001 40002 40003
expect "comma form" 0 "$K" -d 20 127.0.0.1 40001,40002,40003
expect ":udp suffixes" 0 "$K" -u -d 20 127.0.0.1 40001:udp 40002:udp 40003:udp
expect "-d attached value" 0 "$K" -d20 127.0.0.1 40001 40002 40003
expect "two ports refused" 1 "$K" 127.0.0.1 40001,40002
expect "trailing comma refused" 1 "$K" 127.0.0.1 40001,40002,
expect "empty entry refused" 1 "$K" 127.0.0.1 40001,,40003
expect "tcp suffix refused" 1 "$K" 127.0.0.1 40001:tcp 40002 40003
expect "port out of range refused" 1 "$K" 127.0.0.1 40001 40002 70000
expect "-6 refused" 1 "$K" -6 127.0.0.1 40001 40002 40003
expect "bad delay refused" 1 "$K" -d fast 127.0.0.1 40001 40002 40003
expect "unknown option refused" 1 "$K" --tcp 127.0.0.1 40001 40002 40003
expect "a host starting with a dash refused" 1 "$K" -- -oProxyCommand=x 40001 40002 40003
expect "no sequence and no config refused" 1 "$K" 127.0.0.1
expect "KNOCK_PORTS changes the length" 0 env KNOCK_PORTS=2 "$K" -d 20 127.0.0.1 40001 40002
expect "unresolvable host refused" 1 "$K" no-such-host.invalid 40001 40002 40003
expect "KNOCK_BEFORE can stop the knock" 1 env KNOCK_BEFORE='exit 7' "$K" -d 20 127.0.0.1 40001 40002 40003
expect "an unknown sender refused" 1 env KNOCK_SENDER=socat "$K" -d 20 127.0.0.1 40001 40002 40003
expect "--version" 0 "$K" --version

out=$(env -u KNOCK_QUIET "$K" -v -d 20 127.0.0.1 40011 40012 40013 2>&1)
case "$out" in
  *4001[123]*) bad "the sequence is never printed" "$out" ;;
  *) ok "the sequence is never printed" ;;
esac
case "$out" in
  *"shell history"*) ok "ports on the command line draw a note about shell history" ;;
  *) bad "ports on the command line draw a note about shell history" "$out" ;;
esac
out=$("$K" -d 20 127.0.0.1 40011 40012 40013 2>&1)
case "$out" in
  *"shell history"*) bad "KNOCK_QUIET=1 hides the note" "$out" ;;
  *) ok "KNOCK_QUIET=1 hides the note" ;;
esac

conf="$tmp/knock.conf"
printf '# host sequence\n127.0.0.1 40021,40022,40023\n' > "$conf"
out=$(env -u KNOCK_QUIET KNOCK_CONF="$conf" "$K" -d 20 127.0.0.1 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && case "$out" in *"shell history"*) false ;; *) true ;; esac; then
  ok "a sequence from the config file knocks, with no history note"
else
  bad "a sequence from the config file knocks, with no history note" "rc=$rc: $out"
fi

out=$(env -u KNOCK_SENDER "$K" -v -d 20 127.0.0.1 40001 40002 40003 2>&1)
case "$out" in
  *"sender bash"*) ok "bash /dev/udp is the default sender" ;;
  *) bad "bash /dev/udp is the default sender" "$out" ;;
esac

echo "# knock packets"
if command -v "$PY" >/dev/null 2>&1; then
  base=41100
  for sender in bash nc; do
    base=$((base + 10))
    if [ "$sender" = nc ] && ! command -v nc >/dev/null 2>&1; then
      ok "nc sender skipped (nc not installed)"
      continue
    fi
    ports="$((base + 1)),$((base + 2)),$((base + 3))"
    "$PY" "$ROOT/tests/udp_listen.py" "$ports" 8 > "$tmp/listen-$sender" 2>&1 &
    pids+=("$!")
    for _ in $(seq 1 50); do grep -q ready "$tmp/listen-$sender" 2>/dev/null && break; sleep 0.1; done
    KNOCK_SENDER=$sender "$K" -d 200 127.0.0.1 "$ports" > /dev/null 2>&1
    wait "${pids[${#pids[@]} - 1]}"
    got=$(tail -1 "$tmp/listen-$sender")
    want="[{\"port\": $((base + 1)), \"bytes\": 1}, {\"port\": $((base + 2)), \"bytes\": 1}, {\"port\": $((base + 3)), \"bytes\": 1}]"
    if [ "$got" = "$want" ]; then ok "$sender sender: three one-byte datagrams, in order"; else bad "$sender sender: three one-byte datagrams, in order" "got $got"; fi
  done
else
  bad "packet tests need Python 3 (PYTHON=$PY not found)"
fi

echo "# install.sh"
if command -v "$PY" >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
  srv="$tmp/srv/tools/knock"
  mkdir -p "$srv"
  cp "$K" "$srv/knock"
  cp "$ROOT/install.sh" "$srv/install.sh"
  printf '%s  knock\n' "$(sha256_of "$srv/knock")" > "$srv/SHA256SUMS"
  port=18765
  "$PY" -m http.server "$port" --bind 127.0.0.1 --directory "$tmp/srv" > /dev/null 2>&1 &
  pids+=("$!")
  for _ in $(seq 1 50); do curl -fsS "http://127.0.0.1:$port/tools/knock/SHA256SUMS" > /dev/null 2>&1 && break; sleep 0.1; done
  url="http://127.0.0.1:$port"
  sum=$(sha256_of "$K")
  export KNOCK_ALLOW_HTTP=1
  I=(sh "$ROOT/install.sh")

  expect "install from a control plane" 0 "${I[@]}" --server "$url" --dir "$tmp/bin"
  check "installed bytes equal the served script" cmp -s "$tmp/bin/knock" "$K"
  out=$("${I[@]}" --server "$url" --dir "$tmp/bin" 2>&1)
  case "$out" in
    *"warning: no --sha256"*) ok "reinstall without --sha256 warns that the source is unchecked" ;;
    *) bad "reinstall without --sha256 warns that the source is unchecked" "$out" ;;
  esac
  out=$("${I[@]}" --server "$url" --dir "$tmp/bin" --sha256 "$(printf '%s' "$sum" | tr 'a-f' 'A-F')" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] && case "$out" in *warning*) false ;; *) true ;; esac; then
    ok "a matching --sha256 (any case) installs without a warning"
  else
    bad "a matching --sha256 (any case) installs without a warning" "rc=$rc: $out"
  fi
  expect "wrong --sha256 refused" 1 "${I[@]}" --server "$url" --dir "$tmp/bin2" --sha256 "$(printf '0%.0s' $(seq 1 64))"
  check "nothing installed after a --sha256 mismatch" test ! -e "$tmp/bin2/knock"
  expect "a --sha256 that is not 64 hex characters refused" 1 "${I[@]}" --server "$url" --dir "$tmp/bin2" --sha256 "zz${sum:2}"
  expect "a short --sha256 refused" 1 "${I[@]}" --server "$url" --dir "$tmp/bin2" --sha256 "${sum:1}"

  cp "$srv/knock" "$tmp/knock.orig"
  printf '# tampered\n' >> "$srv/knock"
  expect "a download that does not match SHA256SUMS is refused" 1 "${I[@]}" --server "$url" --dir "$tmp/bin5"
  cp "$tmp/knock.orig" "$srv/knock"

  mkdir -p "$tmp/bin3"
  printf '#!/bin/sh\necho other\n' > "$tmp/bin3/knock"
  expect "an existing knock that is not ours is kept" 1 "${I[@]}" --server "$url" --dir "$tmp/bin3"
  check "the other knock is untouched" grep -q other "$tmp/bin3/knock"
  expect "--name installs beside it" 0 "${I[@]}" --server "$url" --dir "$tmp/bin3" --name lattice-knock
  expect "a hidden --name refused" 1 "${I[@]}" --server "$url" --dir "$tmp/bin3" --name .knock

  mkdir -p "$tmp/bin6"
  printf 'victim\n' > "$tmp/victim"
  ln -s "$tmp/victim" "$tmp/bin6/knock"
  expect "a symlink at the target is refused" 1 "${I[@]}" --server "$url" --dir "$tmp/bin6"
  expect "--force replaces the symlink" 0 "${I[@]}" --server "$url" --dir "$tmp/bin6" --force
  check "the symlink's target is not written through" grep -qx victim "$tmp/victim"
  check "the target is now a regular file" test -f "$tmp/bin6/knock" -a ! -L "$tmp/bin6/knock"

  expect "--uninstall removes our copy" 0 "${I[@]}" --uninstall --dir "$tmp/bin"
  check "our copy is gone" test ! -e "$tmp/bin/knock"
  expect "--uninstall refuses a knock that is not ours" 1 "${I[@]}" --uninstall --dir "$tmp/bin3"
  ln -s "$K" "$tmp/bin3/linked"
  expect "--uninstall refuses a symlink" 1 "${I[@]}" --uninstall --dir "$tmp/bin3" --name linked
  expect "plain http refused without the test switch" 1 env -u KNOCK_ALLOW_HTTP "${I[@]}" --server "$url" --dir "$tmp/bin4"
  expect "a non-https mirror refused" 1 env -u KNOCK_ALLOW_HTTP "${I[@]}" --github-mirror "http://mirror.example/" --dir "$tmp/bin4"
else
  bad "install tests need Python 3 and curl"
fi

echo "# ssh check"
if command -v "$PY" >/dev/null 2>&1; then
  start_tcp() {
    "$PY" "$ROOT/tests/tcp_banner.py" "$1" "$2" 20 > "$tmp/tcp-$1" 2>&1 &
    pids+=("$!")
    for _ in $(seq 1 50); do grep -q ready "$tmp/tcp-$1" 2>/dev/null && break; sleep 0.1; done
  }
  start_tcp 42201 banner
  start_tcp 42202 silent
  seq3="42211,42212,42213"

  out=$("$K" -d 20 -c 42201 127.0.0.1 "$seq3" 2>&1)
  rc=$?
  case "$rc:$out" in
    "0:"*"ssh answers"*) ok "-c: an ssh banner counts as open" ;;
    *) bad "-c: an ssh banner counts as open" "rc=$rc: $out" ;;
  esac

  t0=$(date +%s)
  out=$(KNOCK_CHECK_TIMEOUT=1 "$K" -d 20 -c 42202 127.0.0.1 "$seq3" 2>&1)
  rc=$?
  t1=$(date +%s)
  case "$rc:$out" in
    "4:"*"carrier NAT"*) ok "-c: an accepted connection with no banner exits 4 and names the NAT case" ;;
    *) bad "-c: an accepted connection with no banner exits 4 and names the NAT case" "rc=$rc: $out" ;;
  esac
  check "-c: the wait is bounded by KNOCK_CHECK_TIMEOUT" test $((t1 - t0)) -le 4
  case "$out" in
    *4221[123]*) bad "-c: the failure never prints the sequence" "$out" ;;
    *) ok "-c: the failure never prints the sequence" ;;
  esac

  out=$("$K" -d 20 -c 42203 127.0.0.1 "$seq3" 2>&1)
  rc=$?
  check "-c: a closed port exits 4" test "$rc" -eq 4

  out=$(KNOCK_CHECK_PORT=42202 "$K" -d 20 --no-check 127.0.0.1 "$seq3" 2>&1)
  rc=$?
  case "$rc:$out" in
    "0:"*"ssh answers"*) bad "--no-check skips the check" "rc=$rc: $out" ;;
    "0:"*) ok "--no-check skips the check" ;;
    *) bad "--no-check skips the check" "rc=$rc: $out" ;;
  esac
  expect "-c refuses a port that is not a number" 1 "$K" -c ssh 127.0.0.1 "$seq3"
  expect "-c refuses port 0" 1 "$K" -c 0 127.0.0.1 "$seq3"

  # A stand-in for ssh -G: the config maps the alias to 127.0.0.1 and a port,
  # the bare expansion (-F /dev/null) leaves the alias untouched.
  fake="$tmp/fake-ssh"
  cat > "$fake" <<'SH'
#!/bin/sh
if [ "$1" = "-F" ]; then printf 'hostname %s\nport 22\n' "$4"; exit 0; fi
printf 'hostname 127.0.0.1\nport %s\n' "$FAKE_PORT"
if [ -n "${FAKE_JUMP:-}" ]; then printf 'proxyjump %s\n' "$FAKE_JUMP"; fi
SH
  chmod +x "$fake"
  out=$(KNOCK_SSH="$fake" FAKE_PORT=42201 "$K" -d 20 my-alias "$seq3" 2>&1)
  rc=$?
  case "$rc:$out" in
    "0:"*"ssh answers"*) ok "an ssh alias is checked on its own port" ;;
    *) bad "an ssh alias is checked on its own port" "rc=$rc: $out" ;;
  esac
  out=$(KNOCK_SSH="$fake" FAKE_PORT=42202 FAKE_JUMP=bastion "$K" -d 20 my-alias "$seq3" 2>&1)
  rc=$?
  case "$rc:$out" in
    "0:"*"ssh answers"*) bad "an alias behind a jump host is not checked" "rc=$rc: $out" ;;
    "0:"*) ok "an alias behind a jump host is not checked" ;;
    *) bad "an alias behind a jump host is not checked" "rc=$rc: $out" ;;
  esac
  out=$("$K" -d 20 127.0.0.1 "$seq3" 2>&1)
  case "$out" in
    *"ssh answers"*) bad "an address with no -c is not checked" "$out" ;;
    *) ok "an address with no -c is not checked" ;;
  esac
else
  bad "ssh check tests need Python 3 (PYTHON=$PY not found)"
fi

echo "# versions"
kv=$(sed -n 's/^KNOCK_VERSION="\(.*\)"$/\1/p' "$K")
iv=$(sed -n 's/^KNOCK_RELEASE="\(.*\)"$/\1/p' "$ROOT/install.sh")
check "knock $kv and install.sh $iv agree" test "v$kv" = "$iv"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
