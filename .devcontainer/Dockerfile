FROM mcr.microsoft.com/devcontainers/base:jammy

# --- Install Pixi ---
ARG PIXI_VERSION=v0.48.2

RUN curl -L -o /usr/local/bin/pixi -fsSL --compressed "https://github.com/prefix-dev/pixi/releases/download/${PIXI_VERSION}/pixi-$(uname -m)-unknown-linux-musl" \
    && chmod +x /usr/local/bin/pixi \
    && pixi info

# --- Install Apptainer && Conda ---
# Install necessary build dependencies for Apptainer
# Clean up apt cache to keep image size down
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential \
    libseccomp-dev \
    pkg-config \
    squashfs-tools \
    wget \
    git \
    software-properties-common \
    && add-apt-repository -y ppa:apptainer/ppa \
    && apt-get update --quiet \
    && apt-get install --quiet --yes apptainer \
    && wget --quiet https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh \
    && bash Miniforge3-Linux-x86_64.sh -b -p /opt/conda \
    && rm Miniforge3-Linux-x86_64.sh \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set PATH for Conda
ENV PATH="/opt/conda/bin:$PATH"
RUN chown -R vscode:vscode /opt/conda

# set some user and workdir settings to work nicely with vscode
USER vscode
WORKDIR /home/vscode

# Configure Conda
RUN conda config --add channels bioconda \
    && conda config --add channels conda-forge \
    && conda config --set channel_priority strict

RUN echo 'eval "$(pixi completion -s bash)"' >> /home/vscode/.bashrc
