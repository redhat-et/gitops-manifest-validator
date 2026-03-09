FROM registry.access.redhat.com/ubi9/ubi-minimal:9.3

ARG KUBECONFORM_VERSION=0.6.4
ARG PLUTO_VERSION=5.19.4
ARG KUBE_LINTER_VERSION=0.6.8
ARG TARGETARCH=amd64

# Install required packages
RUN microdnf install -y \
    tar \
    gzip \
    jq \
    findutils \
    shadow-utils \
    python3.11 \
    python3.11-pip \
    && microdnf clean all

# Install kubeconform
RUN curl -sL https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}/kubeconform-linux-${TARGETARCH}.tar.gz \
    | tar xz -C /usr/local/bin kubeconform

# Install pluto
RUN curl -sL https://github.com/FairwindsOps/pluto/releases/download/v${PLUTO_VERSION}/pluto_${PLUTO_VERSION}_linux_${TARGETARCH}.tar.gz \
    | tar xz -C /usr/local/bin pluto

# Install kube-linter
RUN curl -sL https://github.com/stackrox/kube-linter/releases/download/v${KUBE_LINTER_VERSION}/kube-linter-linux_${TARGETARCH}.tar.gz \
    | tar xz -C /usr/local/bin

# Create argocd user (UID 999 required by ArgoCD CMP)
RUN useradd -u 999 -g 0 -d /home/argocd argocd

# Create directory structure
RUN mkdir -p /home/argocd/cmp-server/config \
    /home/argocd/scripts \
    /home/argocd/config \
    /home/argocd/.claude/skills \
    && chown -R 999:0 /home/argocd

# Copy skills directory for AI-powered analysis
COPY skills/ /home/argocd/skills/

# Copy scripts
COPY scripts/ /home/argocd/scripts/
COPY plugin.yaml /home/argocd/cmp-server/config/plugin.yaml

# Install Python dependencies
RUN pip3.11 install --no-cache-dir -r /home/argocd/scripts/requirements.txt

# Set permissions
RUN chmod +x /home/argocd/scripts/*.sh /home/argocd/scripts/*.py \
    && chown -R 999:0 /home/argocd \
    && chmod -R g=u /home/argocd

USER 999
WORKDIR /home/argocd

# CMP server entrypoint is provided at runtime via volume mount
