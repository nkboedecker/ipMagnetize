#!/bin/sh
# Written by Claude Code (Anthropic).
#
# Smoke test for a built image: sh test/smoke-test.sh IMAGE
#
# Starts IMAGE on a free loopback port, checks the page, an announce and the
# settings checks in docker-entrypoint.sh, then removes the containers and
# their volumes. Needs docker and curl. The release workflow runs it before
# publishing anything.
set -eu

image=${1:?usage: sh test/smoke-test.sh IMAGE}
name="ipmagnetize-smoke-$$"
tracker="https://tracker.example.test/"
tracker_encoded="https%3A%2F%2Ftracker.example.test%2F"
hash="0123456789abcdef0123456789abcdef01234567"
# the same 20 bytes, percent-encoded, as a BitTorrent client sends info_hash
info_hash="%01%23%45%67%89%ab%cd%ef%01%23%45%67%89%ab%cd%ef%01%23%45%67"
failures=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

cleanup() {
	docker rm -f -v "$name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run -d --name "$name" -p 127.0.0.1::80 -e TRACKER_URL="$tracker" "$image" >/dev/null
addr=$(docker port "$name" 80/tcp | sed -n 1p)
url="http://$addr/"

# Apache takes a moment to start
tries=0
until curl -fs -o /dev/null "$url?hash=$hash"; do
	tries=$((tries + 1))
	if [ "$tries" -ge 30 ]; then
		docker logs "$name"
		echo "FAIL: no answer from the container in 30 seconds"
		exit 1
	fi
	sleep 1
done
pass "the container answers"

location=$(curl -sS -o /dev/null -w '%{redirect_url}' "$url" || true)
if printf '%s\n' "$location" | grep -Eq '\?hash=[0-9a-f]{40}$'; then
	pass "a visit without a hash is sent to a new one"
else
	fail "a visit without a hash went to '$location'"
fi

page=$(curl -fsS "$url?hash=$hash" || true)
case "$page" in
	*"tr=$tracker_encoded\""*) pass "the magnet link uses TRACKER_URL" ;;
	*) fail "the magnet link doesn't use TRACKER_URL" ;;
esac

headers=$(curl -fsS -D - -o /dev/null "$url?hash=$hash" || true)
if printf '%s\n' "$headers" | grep -qi '^x-powered-by:'; then
	fail "responses advertise the PHP version"
else
	pass "responses don't advertise the PHP version"
fi

reply=$(curl -fsS -A "ipmagnetize-smoke-test" "$url?info_hash=$info_hash&peer_id=-SM0001-000000000000&port=6881" || true)
case "$reply" in
	"d14:failure reason"*"IP: "*e) pass "an announce gets a tracker reply" ;;
	*) fail "an announce got '$reply'" ;;
esac

hits=$(curl -fsS "$url?hash=$hash&ajax" || true)
case "$hits" in
	*'"agent":"ipmagnetize-smoke-test"'*) pass "the announce is listed for its hash" ;;
	*) fail "the announce isn't listed: '$hits'" ;;
esac

status=$(curl -s -o /dev/null -w '%{http_code}' "${url}ipmagnetize.db3" || true)
if [ "$status" = 404 ]; then
	pass "the database can't be downloaded"
else
	fail "the database's old address answered $status"
fi

# One-off containers: the entrypoint applies the settings, then runs the
# command given in place of Apache.
default=$(docker run --rm "$image" grep -o 'TRACKER=urlencode("[^"]*")' /var/www/html/index.php || true)
if [ "$default" = 'TRACKER=urlencode("http://localhost/")' ]; then
	pass "TRACKER_URL defaults to http://localhost/"
else
	fail "without TRACKER_URL the tracker is '$default'"
fi

if docker run --rm -e TRACKER_INTERVAL=5m "$image" true >/dev/null 2>&1; then
	fail "the container started with TRACKER_INTERVAL=5m"
else
	pass "the container refuses a TRACKER_INTERVAL that isn't a number"
fi

if docker run --rm -e 'TRACKER_URL=http://a#b/' "$image" true >/dev/null 2>&1; then
	fail "the container started with a # in TRACKER_URL"
else
	pass "the container refuses a TRACKER_URL with a #"
fi

if [ "$failures" -gt 0 ]; then
	echo "--- container log"
	docker logs "$name"
	echo "$failures check(s) failed"
	exit 1
fi
echo "All checks passed"
