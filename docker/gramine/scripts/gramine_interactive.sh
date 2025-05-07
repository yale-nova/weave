#!/bin/bash
docker run --rm -it --privileged \
  --device /dev/isgx \
  --device /dev/sgx_enclave \
  --device /dev/sgx_provision \
  -v "$HOME/.config:/root/.config" \
  gramine-ubuntu \
  bash
