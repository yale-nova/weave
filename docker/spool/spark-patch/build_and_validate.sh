#!/bin/bash
set -euo pipefail

cd spark 

echo "🧹 Cleaning Spark build..."
./build/sbt clean

echo "🧱 Rebuilding all Spark modules with fat JARs..."
./build/sbt assembly

echo "📦 Validating JAR output..."
find assembly/target -name "spark-assembly*.jar" | grep . || {
  echo "❌ Assembly JAR not found!"
  exit 1
}

echo "🔍 Checking for your log injection..."
if find . -name "*.class" -exec strings {} \; | grep -q "Original JVM launch command:"; then
    echo "✅ Found your patch: 'Original JVM launch command'"
else
    echo "❌ Patch NOT found — check your code and rebuild."
    exit 1
fi

echo "🚫 Verifying no stale log string remains..."
if find . -name "*.class" -exec strings {} \; | grep -q "Launch command:"; then
    echo "❌ Found old log: 'Launch command:' — please remove/rename"
    exit 1
else
    echo "✅ No stale 'Launch command:' string found."
fi

echo "🎉 Spark rebuild and validation complete!"
