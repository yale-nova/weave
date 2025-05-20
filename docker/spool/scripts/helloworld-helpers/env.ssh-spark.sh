#!/bin/bash

# Append Spark bin/sbin to PATH if not already present
if [[ ":$PATH:" != *":/opt/spark/bin:"* ]]; then
  export PATH="$PATH:/opt/spark/bin"
fi

if [[ ":$PATH:" != *":/opt/spark/sbin:"* ]]; then
  export PATH="$PATH:/opt/spark/sbin"
fi

# Set SPARK_HOME
export SPARK_HOME="/opt/spark"
