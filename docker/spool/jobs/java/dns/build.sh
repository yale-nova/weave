#!/bin/bash

set -euo pipefail

SRC_DIR="src"
BUILD_DIR="build"
MAIN_CLASS="DnsTest"
JAR_NAME="dns-test.jar"

mkdir -p "$BUILD_DIR"

echo "🔨 Compiling Java source..."
javac -d "$BUILD_DIR" "$SRC_DIR/$MAIN_CLASS.java"

echo "📦 Creating JAR..."
jar cfe "$BUILD_DIR/$JAR_NAME" "$MAIN_CLASS" -C "$BUILD_DIR" "$MAIN_CLASS.class"

echo "✅ Built $BUILD_DIR/$JAR_NAME"

