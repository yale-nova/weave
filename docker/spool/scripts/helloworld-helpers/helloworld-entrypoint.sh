#!/bin/bash
set -e

# Create required Spark log directories
mkdir -p /opt/spark/logs/events
mkdir -p /opt/spark/logs/workers

# Start the SSH daemon
service ssh start

echo "✅ SSH server started and Spark log directories are ready."

