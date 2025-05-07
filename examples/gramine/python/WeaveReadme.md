# Gramine Python Manifest: Customization & Notes

This document describes modifications made to the default `python.manifest.template` in order to successfully run Python 3.10 applications—including NumPy—inside Gramine, without breaking functionality or performance expectations.

---

## ✅ Changes Made

### 1. **Trusted Pycache Write Support**
Gramine, by default, disallows writes to system paths like `/usr/lib/python3.10/__pycache__` which results in dozens of `Disallowing creating file` warnings when Python attempts to compile `.py` files.

To allow safe `.pyc` creation **without opening the entire system directory**, we explicitly added `trusted_files` entries for required paths:

```toml
sgx.trusted_files = [
  ...
  "file:/usr/lib/python3.10/__pycache__/",
  "file:/usr/local/lib/python3.10/dist-packages/",
  ...
]
```

This:
- Silences pycache-related warnings
- Enables full Python functionality (including multiprocessing and NumPy imports)
- Avoids `PermissionError: [Errno 13]` from `.pyc` compilation

### 2. **Manifest Automation Using Jinja Variables**
To reduce hardcoding and improve portability, we used the default variables:
- `{{ entrypoint }}`: the main Python script
- `{{ arch_libdir }}`: target architecture's libdir (e.g., `lib/x86_64-linux-gnu`)
- `python.get_sys_path(entrypoint)`: auto-populates `sys.path` entries for the Python environment

This enables the manifest to work on multiple Ubuntu images and with upgraded Python versions as long as paths are correctly mapped.

### 3. **Environment Configuration**
Added:

```toml
loader.env.LD_LIBRARY_PATH = "/lib:/lib:{{ arch_libdir }}:/usr/{{ arch_libdir }}"
loader.env.OMP_NUM_THREADS = "4"
```

These provide:
- Dynamic linking support inside enclaves
- Explicit threading limit to avoid NumPy over-allocation (while keeping multithreading allowed)

---

## 💡 Remaining Known Warnings (Ignored)

The following warnings are known and **safe to ignore** in our use case:

### ⚠️ `FUTEX_CLOCK_REALTIME` Warning
```
(libos_futex.c:755:_libos_syscall_futex) warning: Ignoring FUTEX_CLOCK_REALTIME flag
```
- Origin: NumPy or threading libraries using real-time clocks with futex.
- Gramine currently does not implement `FUTEX_CLOCK_REALTIME`.
- ✅ **We do not rely on exact real-time wakeups**, so this has no functional impact.

---

## 🛠️ What Still Doesn’t Work (and Is Out of Scope)

- **System calls not supported by Gramine (e.g., `clone3`, `rseq`)**:
  - These are rare and have no observed effect on workload correctness.
  - Rewriting library internals or kernel support is not planned.

- **Fine-grained `__pycache__` path whitelisting**:
  - Instead of enumerating individual `.pyc` files, we trust broader directories.

---

## ✅ Test Cases Passed

- `helloworld.py`: Basic execution
- `test-numpy.py`: NumPy import, matrix operations, dot product

---

## 🔒 Security Note

We kept `loader.insecure__use_host_env = true` and `loader.insecure__use_cmdline_argv = true` for convenience during development. For production:
- Review these flags
- Use manifest signing
- Restrict `fs.mounts` and `sgx.trusted_files` to minimal necessary surface

---

### 🛠 Dependency Management with Poetry

This project uses [Poetry](https://python-poetry.org/) to manage Python dependencies, installed globally **inside the container**.

> ⚠️ **Important:** Virtual environments are explicitly disabled to ensure compatibility with Gramine's Python runtime. This makes all packages available to the system Python used by Gramine.

This is configured automatically in the `Makefile` via:

```make
poetry config virtualenvs.create false --local

## 🧠 Contributors

Mahdi Soleimani — Yale CS PhD  
Changes based on `gramineproject/gramine@8fc123d`
