# Scala Fat JAR Test Suite for Gramine

This repository contains a set of Scala-based test cases compiled into fat JARs for evaluating JVM behavior inside [Gramine](https://gramine.dev) enclaves. These test cases are designed to reflect real-world Spark worker behavior like file I/O, concurrency, memory stress, and networking.

---

## 🔧 Project Structure

```
.
├── src/main/scala/           # Scala test sources
├── jars/                     # Compiled fat JARs
├── data/                     # Input files for tests
├── output-data/              # Output files from tests
├── test-logs/                # Logs from Gramine/nativetests
├── scripts/                  # Build/test scripts
├── project/, build.sbt       # SBT project setup
├── java.manifest.template    # Gramine manifest template
├── Makefile                  # Unified build + test driver
```

---

## 🚀 Quick Start

### 1. Install Dependencies
```bash
make deps
```

### 2. Build Fat JARs
```bash
make
```

### 3. Run Tests
- Run tests natively:
```bash
make run-native
```

- Run tests in Gramine (if installed):
```bash
make run-gramine
```

- Auto-detect Gramine and fallback if needed:
```bash
make check
```

---

## 📦 Available Test Cases

| Test Class         | Purpose                                |
|--------------------|-----------------------------------------|
| HelloWorld         | Print hello from inside enclave         |
| WordCount          | Word frequency count with I/O           |
| FileShuffle        | Shuffle file lines using tempfiles      |
| BigFileScan        | Write & scan large file (1M lines)      |
| GCStressTest       | Trigger JVM GC actively                 |
| MultiThreadMain    | 10,000 threads incrementing a counter   |
| NetEchoServer      | Echo server with timeout (port 0 bind)  |
| NetEchoRoundtrip   | Client/server echo in one process       |
| HttpGetTest        | HTTPS GET and JSON fetch (optional)     |

---

## ⚙️ Fat JAR Details

Each Scala test is compiled to a standalone fat JAR using `sbt-assembly`. This bundles:
- Scala standard library
- Test class and any internal dependencies

This allows JARs to be run directly:
```bash
java -jar jars/WordCount.jar
```

---

## 🔐 Gramine Manifest Setup

### Mounted Paths
- `/usr`, `/lib`, `arch_libdir`: JVM support
- `jars/`: Location of fat JARs
- `data/`, `output-data/`: For file-based tests
- `/dev/urandom`: For safe seeding `Random()`

### Notes
- `/tmp` is simulated by Gramine — temp files work without mounting
- No need to mount entire `/dev/`, only list `/dev/urandom` in `sgx.trusted_files`

---

## 🧠 Developer Tips

- Rebuild only changed JARs:
```bash
./scripts/build-fatjars.sh --no-rebuild
```

- Check whether Gramine is available:
```bash
which gramine-direct
```

- Add new test: place `MyTest.scala` in `src/main/scala/`, then `make`

---

## 🛠 Future Plans

- Add multi-threaded shuffle worker
- Simulate mini DAG scheduler
- Add network fault injection tests
- Add temp-spill + checkpoint simulation

