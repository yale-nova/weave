# Weave Java Example

This directory contains a Weave-enhanced version of the Java Gramine example. It provides a framework for testing Java applications under Gramine, with automated output validation, dependency management, and Docker integration for reproducible builds.

## 🧹 Key Enhancements Over Gramine Base

Compared to the [original Gramine Java example](https://gramineproject.io/), this version introduces several improvements:

- ✅ **Automated Testing Script**: Runs Java examples with and without Gramine and verifies that outputs match.
- 🧪 **Reference Output Comparison**: Automatically generates reference outputs outside Gramine and validates Gramine runs against them.
- 📆 **System Dependency Checks**: Ensures packages like `openjdk-11-jdk` are installed (in-container installation supported).
- 📉 **Manifest Generation & Signing**: Builds `java.manifest`, `java.manifest.sgx`, and `java.sig` cleanly.
- 📁 **SGX Support**: Toggle with `SGX=1` to enable SGX enclave configuration.
- 📂 **Isolated Output Structure**: Logs, output, and references are saved to organized subdirectories.

## 📦 Installing Dependencies

On Ubuntu systems, install Java and build tools:

```bash
sudo apt-get install openjdk-11-jdk make coreutils
```

Inside containers, `make deps` can install missing packages automatically.

## ⚙️ Build and Run Instructions

### Without SGX

```bash
make
make check
```

### With SGX

```bash
make SGX=1
make SGX=1 check
```

### Run an Example Manually

```bash
gramine-direct java -jar jars/WordCount.jar
gramine-sgx java -Xmx8G -jar jars/WordCount.jar
```

## 📁 Output Structure

- `test-outputs/` — Reference output from Java execution outside Gramine
- `test-logs/` — Logs of Gramine execution per test
- `output-data/` — Writable Gramine volume (e.g., for file outputs)

## 🚫 Known Quirks

### ❗ `.class` Files Randomly Deleted

We observed that compiled `.class` files in `build/` are sometimes **automatically removed after test execution**, even though no `rm` command is present in the Makefile or test scripts. The cause is suspected to be how `jar` is invoked:

```make
jar cfe $@ MainClassName -C build .
```

This may unintentionally trigger deletion if `build/` is interpreted as an input/output target.

#### ✅ Workaround
To avoid this, package only the required `.class` file:
```make
jar cfe $@ MainClassName -C build MainClassName.class
```

This behavior is harmless but can lead to surprising diffs and failing incremental builds.

## 📒 Files Overview

- `Makefile` — Build logic for compiling, manifesting, and testing
- `run-java-tests.sh` — Script for generating and validating Java outputs
- `java.manifest.template` — Base template for Gramine manifest generation

---

This setup is designed to seamlessly support Java testing in both direct and SGX-backed Gramine environments, while remaining clean and extensible.



