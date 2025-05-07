# ---------- Stage 1: Clone repos ----------
FROM ubuntu:22.04 AS clone-stage

ARG DEBIAN_FRONTEND=noninteractive
ARG DEBUG_LOGGING=0
ENV DEBUG_LOGGING=${DEBUG_LOGGING}

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    jq && \
    rm -rf /var/lib/apt/lists/*

COPY ./private-clones/repos.tar.gz /tmp/repos.tar.gz
RUN mkdir -p /opt/private-repos && \
    tar -xzf /tmp/repos.tar.gz -C /opt/private-repos && \
    rm -f /tmp/repos.tar.gz

COPY private-clones/.repos-hash /opt/private-repos/.repos-hash
COPY private_repos.conf /opt/private-repos/private_repos.conf

# ---------- Stage 2: Install base packages ----------
FROM ubuntu:22.04 AS base-deps

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    autoconf \
    bison \
    gawk \
    nasm \
    ninja-build \
    pkg-config \
    python3 \
    python3-click \
    python3-jinja2 \
    python3-pip \
    python3-pyelftools \
    python3-pytest \
    wget \
    libunwind8 \
    musl-tools \
    curl \
    gnupg \
    lsb-release \
    sudo \
    git \
    make \
    vim \
    bash && \
    rm -rf /var/lib/apt/lists/*

# Install ca-certificates separately for fallback protection
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/* || true

RUN python3 -m pip install --no-cache-dir 'meson>=0.56' 'tomli>=1.1.0' 'tomli-w>=0.4.0'

# ---------- Stage 3: Add Java and All System Deps ----------
FROM base-deps AS java-build

# Step 1: Install yq manually (and cache it separately)
RUN curl -sL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq

# Step 2: Copy system-deps parsing scripts only (no repos again!)
COPY scripts/parse-system-deps.sh /opt/scripts/parse-system-deps.sh
COPY scripts/install-deps-from-lock.sh /opt/scripts/install-deps-from-lock.sh

# Step 3: Parse system dependencies
RUN chmod +x /opt/scripts/*.sh && \
    bash /opt/scripts/parse-system-deps.sh /opt/private-repos 

# Step 4: Install all system dependencies based on lockfile
RUN bash /opt/scripts/install-deps-from-lock.sh /opt/system-deps.lock

# Step 5: cleanup. 
RUN rm -rf /opt/scripts  # ⬅️ Delete scripts only after both done

# Step 6: Install Java (since it's part of declared deps anyway)
RUN apt-get update && apt-get install -y --no-install-recommends openjdk-11-jdk && \
    rm -rf /var/lib/apt/lists/*

# ---------- Stage 4: Runtime Gramine Base ----------
FROM java-build AS runtime

# Add Gramine repo
RUN echo "📥 Fetching Gramine repo key..." && \
    curl -fsSLo /usr/share/keyrings/gramine-keyring.gpg https://packages.gramineproject.io/gramine-keyring.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/gramine-keyring.gpg] https://packages.gramineproject.io/ $(lsb_release -sc) main" \
        > /etc/apt/sources.list.d/gramine.list

# Add Intel SGX repo
RUN echo "📥 Fetching Intel SGX repo key..." && \
    curl -fsSLo /usr/share/keyrings/intel-sgx-deb.asc https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/intel-sgx-deb.asc] https://download.01.org/intel-sgx/sgx_repo/ubuntu $(lsb_release -sc) main" \
        > /etc/apt/sources.list.d/intel-sgx.list

# Update package index
RUN echo "🔄 Running apt-get update..." && \
    apt-get update

# Install Gramine with logging
RUN echo "📦 Installing Gramine..." && \
    mkdir -p /log && \
    apt-get install -y gramine 2>&1 | tee /log/gramine_install.log || { \
        echo '❌ Gramine installation failed'; \
        cat /log/gramine_install.log; \
        exit 1; }

# Cleanup
RUN echo "🧹 Cleaning up apt cache..." && \
    rm -rf /var/lib/apt/lists/*

# Copy repo content
COPY --from=clone-stage /opt/private-repos /opt/private-repos
COPY Makefile.global /opt/private-repos/Makefile

# Make scripts executable
RUN echo "🔧 Marking scripts as executable..." && \
    find /opt/private-repos -type f -name "*.sh" -exec chmod +x {} + && \
    find /opt/private-repos -type f -name "*.py" -exec grep -q "^#\!.*python" {} \; -exec chmod +x {} + || true

# Add SGX checker
COPY scripts/check-sgx.sh /usr/local/bin/check-sgx.sh
RUN chmod +x /usr/local/bin/check-sgx.sh

# ---------- Stage 5: Optional test stage (make, poetry, netcat) ----------
FROM runtime AS make-repos

ARG DEBUG_LOGGING=0
ENV DEBUG_LOGGING=${DEBUG_LOGGING}
ENV WEAVE_IN_CONTAINER=1

# 1. Install netcat (for HTTP server/client tests)
RUN apt-get update && apt-get install -y netcat-openbsd && rm -rf /var/lib/apt/lists/*

# 2. Install Poetry globally
RUN echo "📦 Installing Poetry..." && \
    curl -sSL https://install.python-poetry.org | python3 - && \
    echo "✅ Poetry installed successfully."

# 3. Make sure `poetry` is in PATH
ENV PATH="/root/.local/bin:$PATH"

# Optional sanity check to ensure Poetry is available
RUN echo "🔍 Checking if Poetry is on PATH..." && \
    if ! command -v poetry >/dev/null 2>&1; then \
        echo "❌ Poetry installation failed or not in PATH"; \
        exit 1; \
    else \
        echo "✅ Poetry is available: $(which poetry)"; \
    fi

# 4. Run `poetry config` to disable venvs inside containers
RUN echo "⚙️  Configuring Poetry for container..." && \
    poetry config virtualenvs.create false --local || true

# 5. Run Poetry dependency install across all private repos
#    This assumes each has `pyproject.toml`
COPY --from=clone-stage /opt/private-repos /opt/private-repos
COPY Makefile.global /opt/private-repos/Makefile

RUN find /opt/private-repos -type f -name "*.sh" -exec chmod +x {} + && \
    find /opt/private-repos -type f -name "*.py" -exec grep -q "^#\!.*python" {} \; -exec chmod +x {} + || true

# Run poetry setup (mimicking `make setup`)
RUN echo "📦 Installing Python deps via Poetry..." && \
    for dir in $(find /opt/private-repos -type f -name pyproject.toml -exec dirname {} \;); do \
        echo "🔍 Processing $dir" && cd "$dir" && \
        poetry lock && \
        poetry install --no-root; \
    done


# 6. Clean + Build
RUN mkdir -p /log && \
    if [ "$DEBUG_LOGGING" = "1" ]; then \
        echo "🧹 Logging make clean output to /log/make_clean.log" && \
        make -C /opt/private-repos clean > /log/make_clean.log 2>&1 || (cat /log/make_clean.log && exit 1); \
    else \
        make -C /opt/private-repos clean; \
    fi

RUN if [ "$DEBUG_LOGGING" = "1" ]; then \
        echo "🛠️  Logging make all output to /log/make_all.log" && \
        make -C /opt/private-repos all > /log/make_all.log 2>&1 || (cat /log/make_all.log && exit 1); \
    else \
        make -C /opt/private-repos all; \
    fi

# ---------- Stage 6a: Final image with tests ----------
FROM make-repos AS final-with-tests

WORKDIR /workspace
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash", "-c", "echo ✅ Container is running with tests. && tail -f /dev/null"]

# ---------- Stage 6b: Final image without tests ----------
FROM runtime AS final-without-tests

WORKDIR /workspace
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash", "-c", "echo ✅ Container is running with minimal setting. && tail -f /dev/null"]

