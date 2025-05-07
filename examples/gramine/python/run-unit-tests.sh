#!/usr/bin/env bash

set -e

GRAMINE_BIN=${GRAMINE_BIN:-gramine-direct}

echo "🧪 Phase 1: Running unit tests (default build)"
$GRAMINE_BIN python -m unittest discover -s tests > log_default.txt 2>&1 || {
    echo "❌ Tests failed (default build)"
    cat log_default.txt
    exit 1
}

echo "🧹 Cleaning and rebuilding with EDMM=1"
make clean && make EDMM=1

echo "🧪 Phase 2: Running unit tests (EDMM build)"
$GRAMINE_BIN python -m unittest discover -s tests > log_edmm.txt 2>&1 || {
    echo "❌ Tests failed (EDMM build)"
    cat log_edmm.txt
    exit 1
}

echo "✅ All unit tests passed successfully!"

