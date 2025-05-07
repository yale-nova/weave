#!/usr/bin/env bash

# Copyright (C) 2023 Gramine contributors
# SPDX-License-Identifier: BSD-3-Clause

set -e

is_in_container() {
    grep -qE '/docker|/lxc|/kubepods' /proc/1/cgroup 2>/dev/null || \
    [ -f /.dockerenv ] || \
    [ "$WEAVE_IN_CONTAINER" = "1" ]
}

if test -n "$SGX"
then
    GRAMINE=gramine-sgx
else
    GRAMINE=gramine-direct
fi

# === helloworld ===
echo -e "\n\nRunning helloworld.py:"
$GRAMINE ./python scripts/helloworld.py > OUTPUT
grep -q "Hello World" OUTPUT && echo "[ Success 1/4 ]"
rm OUTPUT

# === web server and client (on port 8005) ===
echo -e "\n\nRunning HTTP server dummy-web-server.py in the background:"
$GRAMINE ./python scripts/dummy-web-server.py 8005 & echo $! > server.PID

# Check if netcat is available
if ! command -v nc >/dev/null 2>&1; then
    echo "⚠️  'nc' (netcat) is not installed."

    if is_in_container && [ "$(id -u)" = "0" ] && command -v apt-get >/dev/null 2>&1; then
        echo "🔧 Running in container — attempting to install netcat..."
        apt-get update && apt-get install -y --no-install-recommends netcat-openbsd
    else
        echo "❌ 'nc' is required but could not be auto-installed outside container."
        echo "   Please install it manually: sudo apt-get install -y netcat-openbsd"
        exit 1
    fi
fi

./scripts/wait-for-server.sh 300 127.0.0.1 8005

echo -e "\n\nRunning HTTP client test-http.py:"
$GRAMINE ./python scripts/test-http.py 127.0.0.1 8005 > OUTPUT1
wget -q http://127.0.0.1:8005/ -O OUTPUT2
echo >> OUTPUT2  # include newline since wget doesn't add it
diff OUTPUT1 OUTPUT2 | grep -q '^>' || echo "[ Success 2/4 ]"
kill "$(cat server.PID)"
rm -f OUTPUT1 OUTPUT2 server.PID

# === numpy ===
$GRAMINE ./python scripts/test-numpy.py > OUTPUT
grep -q "dot: " OUTPUT && echo "[ Success 3/4 ]"
rm OUTPUT

# === scipy ===
$GRAMINE ./python scripts/test-scipy.py > OUTPUT
grep -q "cholesky: " OUTPUT && echo "[ Success 4/4 ]"
rm OUTPUT

# === fork test ===
echo -e "\n\nRunning fork test:"
$GRAMINE ./python scripts/test-forks.py > OUTPUT
grep -q "Parent: child finished" OUTPUT && echo "[ Success 5/4 - fork test ]"
rm OUTPUT

# === SGX quote ===
if test -n "$SGX"
then
    $GRAMINE ./python scripts/sgx-report.py > OUTPUT
    grep -q "Generated SGX report" OUTPUT && echo "[ Success SGX report ]"
    rm OUTPUT

    $GRAMINE ./python scripts/sgx-quote.py > OUTPUT
    grep -q "Extracted SGX quote" OUTPUT && echo "[ Success SGX quote ]"
    rm OUTPUT
fi

