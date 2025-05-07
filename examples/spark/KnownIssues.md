# Known Issues and Warnings

This document records known Spark warnings and minor setup quirks observed during launching the Spark Master.

The core system is fully functional and stable. These warnings are harmless unless otherwise noted.

---

## 1. Hostname Resolves to Loopback Address

**Warning:**
```
[WARN] Utils: Your hostname resolves to a loopback address: 127.0.0.1; using 192.168.x.x instead (on interface eth0)
[WARN] Utils: Set SPARK_LOCAL_IP if you need to bind to another address
```

**Cause:**
- Spark detects that the machine hostname (`SandboxHost-...`) maps to `127.0.0.1`.
- It automatically picks a real network IP like `192.168.x.x`.

**Impact:**
- None in standalone Spark setups.
- It matters only in multi-node distributed clusters.

**Polish Fix (optional):**
Before launching the Spark Master, export a real IP manually:
```bash
export SPARK_LOCAL_IP="192.168.x.x"
```

---

## 2. Native Hadoop Library Not Found

**Warning:**
```
[WARN] NativeCodeLoader: Unable to load native-hadoop library for your platform... using builtin-java classes where applicable
```

**Cause:**
- Hadoop native libraries are not installed.
- Spark falls back to Java implementations.

**Impact:**
- No problem for local Spark or Standalone cluster mode.
- Matters only if connecting to real HDFS clusters.

**Polish Fix (optional):**
- Install Hadoop native libraries (not necessary for current setup).

---

## 3. Illegal Reflective Access Warning

**Warning:**
```
WARNING: An illegal reflective access operation has occurred
```

**Cause:**
- Spark 3.2.2 uses Java internal APIs (like `DirectByteBuffer`) not officially exposed by Java 11+.

**Impact:**
- Currently only a warning.
- Future Java versions (17+) may block it.

**Polish Fix (optional):**
- Before launching the Spark Master, add JVM flags:
```bash
export SPARK_DAEMON_JAVA_OPTS="$SPARK_DAEMON_JAVA_OPTS --add-opens java.base/java.nio=ALL-UNNAMED"
```
- Or upgrade Spark to 3.3.2 or 3.4.x+ where this issue is reduced.

---

## 4. Variables inside log4j.properties

**Issue:**
- `log4j.properties` files do **not** automatically substitute shell environment variables like `${SPARK_LOG_DIR}` or `${SPARK_LOG_LEVEL}`.
- A manual replacement (`sed`) is done during the configuration script to hardcode the correct paths and levels.

**Impact:**
- None. Resolved at setup time.

---

# Final Status

| Warning Type               | Impact  | Action Taken |
|:----------------------------|:--------|:-------------|
| Hostname resolves to loopback | None   | Can export `SPARK_LOCAL_IP` for polish |
| Native Hadoop not found     | None    | Ignored safely |
| Illegal Reflective Access   | Minor   | Can export `--add-opens` for polish |
| log4j property variables    | None    | Manually substituted during setup |

✅ System is fully working and robust.
✅ Warnings are documented and optionally fixable if professional polish is needed.

---

# Tips
- These warnings are common even in large production Spark clusters unless heavily customized.
- Always test functionality before worrying about warnings.
- Future Spark versions will automatically fix many of these without manual interventions.

---

# End of KnownIssues.Readme


