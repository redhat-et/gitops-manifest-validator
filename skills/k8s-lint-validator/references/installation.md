## Installation Guide

Instructions for installing kube-linter, kubeconform, and pluto on all platforms.

---

## kube-linter

**Source**: [stackrox/kube-linter on GitHub](https://github.com/stackrox/kube-linter)

### macOS

```bash
# Using Homebrew
brew install kube-linter

# Or download binary
curl -LO https://github.com/stackrox/kube-linter/releases/latest/download/kube-linter-darwin
chmod +x kube-linter-darwin
sudo mv kube-linter-darwin /usr/local/bin/kube-linter
```

### Linux

```bash
# Download and install latest version
curl -LO https://github.com/stackrox/kube-linter/releases/latest/download/kube-linter-linux
chmod +x kube-linter-linux
sudo mv kube-linter-linux /usr/local/bin/kube-linter
```

### Windows

```powershell
# Download from releases
curl -LO https://github.com/stackrox/kube-linter/releases/latest/download/kube-linter.exe
# Move to PATH directory
move kube-linter.exe C:\Windows\System32\
```

### Verify Installation

```bash
kube-linter version
```

---

## kubeconform

**Source**: [yannh/kubeconform on GitHub](https://github.com/yannh/kubeconform)

### macOS

```bash
# Using Homebrew
brew install kubeconform

# Or download binary
curl -LO https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-darwin-amd64.tar.gz
tar xf kubeconform-darwin-amd64.tar.gz
chmod +x kubeconform
sudo mv kubeconform /usr/local/bin/
```

### Linux

```bash
# Download and install
curl -LO https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz
tar xf kubeconform-linux-amd64.tar.gz
chmod +x kubeconform
sudo mv kubeconform /usr/local/bin/
```

### Windows

```powershell
# Download from releases
curl -LO https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-windows-amd64.zip
# Extract and move to PATH
Expand-Archive kubeconform-windows-amd64.zip
move kubeconform-windows-amd64\kubeconform.exe C:\Windows\System32\
```

### Verify Installation

```bash
kubeconform -v
```

---

## pluto

**Source**: [FairwindsOps/pluto on GitHub](https://github.com/FairwindsOps/pluto)

### macOS

```bash
# Using Homebrew
brew install FairwindsOps/tap/pluto

# Or download binary
curl -LO https://github.com/FairwindsOps/pluto/releases/latest/download/pluto_5_darwin_amd64.tar.gz
tar xzf pluto_5_darwin_amd64.tar.gz
chmod +x pluto
sudo mv pluto /usr/local/bin/
```

### Linux

```bash
# Download and install
curl -LO https://github.com/FairwindsOps/pluto/releases/latest/download/pluto_5_linux_amd64.tar.gz
tar xzf pluto_5_linux_amd64.tar.gz
chmod +x pluto
sudo mv pluto /usr/local/bin/
```

### Windows

```powershell
# Download from releases
curl -LO https://github.com/FairwindsOps/pluto/releases/latest/download/pluto_5_windows_amd64.zip
Expand-Archive pluto_5_windows_amd64.zip
move pluto_5_windows_amd64\pluto.exe C:\Windows\System32\
```

### Verify Installation

```bash
pluto version
```

---

## All-in-One Installation Script

### Linux/macOS

Save as `install-linters.sh`:

```bash
#!/bin/bash
set -e

echo "Installing Kubernetes linting tools..."

# Detect OS
OS="$(uname -s)"
case "${OS}" in
    Linux*)     PLATFORM=linux;;
    Darwin*)    PLATFORM=darwin;;
    *)          echo "Unsupported OS: ${OS}"; exit 1;;
esac

# Install kube-linter
echo "Installing kube-linter..."
curl -LO "https://github.com/stackrox/kube-linter/releases/latest/download/kube-linter-${PLATFORM}"
chmod +x "kube-linter-${PLATFORM}"
sudo mv "kube-linter-${PLATFORM}" /usr/local/bin/kube-linter

# Install kubeconform
echo "Installing kubeconform..."
curl -LO "https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-${PLATFORM}-amd64.tar.gz"
tar xf "kubeconform-${PLATFORM}-amd64.tar.gz"
chmod +x kubeconform
sudo mv kubeconform /usr/local/bin/
rm "kubeconform-${PLATFORM}-amd64.tar.gz"

# Install pluto
echo "Installing pluto..."
curl -LO "https://github.com/FairwindsOps/pluto/releases/latest/download/pluto_5_${PLATFORM}_amd64.tar.gz"
tar xzf "pluto_5_${PLATFORM}_amd64.tar.gz"
chmod +x pluto
sudo mv pluto /usr/local/bin/
rm "pluto_5_${PLATFORM}_amd64.tar.gz"

echo "✓ All tools installed successfully!"
echo ""
echo "Verify installation:"
echo "  kube-linter version"
echo "  kubeconform -v"
echo "  pluto version"
```

Run with:
```bash
chmod +x install-linters.sh
./install-linters.sh
```

---

## Docker Images

If you prefer containerized tools:

### kube-linter

```bash
docker run --rm -v $(pwd):/workdir stackrox/kube-linter:latest lint /workdir/deployment.yaml
```

### kubeconform

```bash
docker run --rm -v $(pwd):/data ghcr.io/yannh/kubeconform:latest /data/deployment.yaml
```

### pluto

```bash
docker run --rm -v $(pwd):/workdir us-docker.pkg.dev/fairwinds-ops/oss/pluto:latest detect-files -d /workdir
```

---

## CI/CD Integration

### GitHub Actions

Add to workflow:

```yaml
- name: Install Linting Tools
  run: |
    # kube-linter
    curl -L https://github.com/stackrox/kube-linter/releases/latest/download/kube-linter-linux -o kube-linter
    chmod +x kube-linter && sudo mv kube-linter /usr/local/bin/

    # kubeconform
    curl -L https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz | tar xz
    chmod +x kubeconform && sudo mv kubeconform /usr/local/bin/

    # pluto
    curl -L https://github.com/FairwindsOps/pluto/releases/latest/download/pluto_5_linux_amd64.tar.gz | tar xz
    chmod +x pluto && sudo mv pluto /usr/local/bin/
```

---

## Troubleshooting

### Permission Denied

If you get "permission denied", ensure the binary is executable:
```bash
chmod +x /usr/local/bin/kube-linter
chmod +x /usr/local/bin/kubeconform
chmod +x /usr/local/bin/pluto
```

### Command Not Found

Add to your PATH:
```bash
export PATH=$PATH:/usr/local/bin
```

Or move binaries to a directory already in PATH:
```bash
sudo mv kube-linter /usr/bin/
```

---

## References

- [kube-linter GitHub](https://github.com/stackrox/kube-linter)
- [kube-linter Documentation](https://docs.kubelinter.io/)
- [kubeconform GitHub](https://github.com/yannh/kubeconform)
- [pluto GitHub](https://github.com/FairwindsOps/pluto)
