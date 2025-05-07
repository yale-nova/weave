#!/bin/bash

echo "🔍 Checking SGX availability..."
is-sgx-available | tee ./sgx_check.log

echo "🔑 Ensuring Gramine RSA 3072 key is generated..."
gramine-sgx-gen-private-key

KEY_PATH="$HOME/.config/gramine/enclave-key.pem"
if [ -f "$KEY_PATH" ]; then
    echo "✅ Key created successfully at $KEY_PATH"
else
    echo "❌ Failed to create enclave signing key!"
    exit 1
fi
