# Weave

This repository consolidates the runtime infrastructure and Gramine configurations for Weave, our confidential computing framework built on top of Spark. Specifically, it integrates two systems: [Weave](https://github.com/MattSlm/spark-weave-shuffle), a memory-oblivious shuffler that mitigates access pattern and speculative execution leaks, and [Spool](https://github.com/MattSlm/spark-spool), a lightweight context generator that minimizes enclave overhead. This repo provides streamlined Gramine manifests, Spark environment tuning, and reproducible test cases for JVM, Scala, and Spark workloads running inside enclaves.

### Container Detection for Global Installs

This project disables Poetry's virtual environments *only inside containers* (Docker, Azure ACI, etc.) using the following detection:

- `/proc/1/cgroup` contains container keywords
- Presence of `/.dockerenv`
- Or if you set: `export WEAVE_IN_CONTAINER=1`

Outside containers, Poetry continues to use isolated virtual environments to avoid polluting the host Python setup.

> You can force container behavior manually by setting:
> ```bash
> export WEAVE_IN_CONTAINER=1
> ```
