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
    unzip \
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

# Step 1: Install yq manually
RUN curl -sL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq

# Step 2: Copy system-deps parsing scripts only
COPY scripts/parse-system-deps.sh /opt/scripts/parse-system-deps.sh
COPY scripts/install-deps-from-lock.sh /opt/scripts/install-deps-from-lock.sh

# Step 3: Parse and install system dependencies
RUN chmod +x /opt/scripts/*.sh && \
    bash /opt/scripts/parse-system-deps.sh /opt/private-repos && \
    bash /opt/scripts/install-deps-from-lock.sh /opt/system-deps.lock

# Cleanup scripts
# RUN rm -rf /opt/scripts

# Step 4: Install Java
RUN apt-get update && apt-get install -y --no-install-recommends openjdk-11-jdk && \
    rm -rf /var/lib/apt/lists/*

# ---------- Stage 4: Runtime Gramine Base ----------
FROM java-build AS runtime

# Add Gramine repo
RUN curl -fsSLo /usr/share/keyrings/gramine-keyring.gpg https://packages.gramineproject.io/gramine-keyring.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/gramine-keyring.gpg] https://packages.gramineproject.io/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/gramine.list

# Add Intel SGX repo
RUN curl -fsSLo /usr/share/keyrings/intel-sgx-deb.asc https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/intel-sgx-deb.asc] https://download.01.org/intel-sgx/sgx_repo/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/intel-sgx.list

# Install Gramine
RUN apt-get update && \
    mkdir -p /log && \
    apt-get install -y gramine 2>&1 | tee /log/gramine_install.log || { cat /log/gramine_install.log; exit 1; }

# Final cleanup
RUN rm -rf /var/lib/apt/lists/*

# Copy repo content
COPY --from=clone-stage /opt/private-repos /opt/private-repos
COPY Makefile.global /opt/private-repos/Makefile

# Make scripts executable
RUN find /opt/private-repos -type f -name "*.sh" -exec chmod +x {} + && \
    find /opt/private-repos -type f -name "*.py" -exec grep -q "^#\!.*python" {} \; -exec chmod +x {} + || true

# Add SGX checker
COPY scripts/check-sgx.sh /usr/local/bin/check-sgx.sh
RUN chmod +x /usr/local/bin/check-sgx.sh

# ---------- Install Spark ----------
# Copy local spark directory to /opt/spark
COPY built-spark /opt/spark

# Optional: verify contents after copy
RUN echo "✅ Verifying /opt/spark contents:" && ls -l /opt/spark

# Set Spark environment
ENV SPARK_HOME=/opt/spark
ENV PATH="${PATH}:${SPARK_HOME}/bin:${SPARK_HOME}/sbin"

COPY weave-serial /opt/weave-serial

RUN cp /opt/weave-serial/target/scala-2.12/spark-weave-shuffle_2.12-0.1.0.jar /opt/spark/jars

# ---------- Final Stage ----------
FROM runtime AS final

WORKDIR /workspace
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash", "-c", "echo ✅ Container is running with minimal setting. && tail -f /dev/null"]
