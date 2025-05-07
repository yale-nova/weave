#!/bin/bash

az container exec \
  --resource-group weave-ae \
  --name weavec1 \
  --exec-command "/usr/local/bin/check-sgx.sh"

