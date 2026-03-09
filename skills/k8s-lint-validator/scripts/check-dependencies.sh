#!/bin/bash
# Check if required linting tools are installed

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Checking Kubernetes linting tool dependencies..."
echo ""

ALL_INSTALLED=true

# Check kube-linter
if command -v kube-linter &> /dev/null; then
    VERSION=$(kube-linter version 2>&1 | head -n1)
    echo -e "${GREEN}✓${NC} kube-linter installed: $VERSION"
else
    echo -e "${RED}✗${NC} kube-linter not installed"
    ALL_INSTALLED=false
fi

# Check kubeconform
if command -v kubeconform &> /dev/null; then
    VERSION=$(kubeconform -v 2>&1 || echo "installed")
    echo -e "${GREEN}✓${NC} kubeconform installed: $VERSION"
else
    echo -e "${RED}✗${NC} kubeconform not installed"
    ALL_INSTALLED=false
fi

# Check pluto
if command -v pluto &> /dev/null; then
    VERSION=$(pluto version 2>&1 | grep -i version || echo "installed")
    echo -e "${GREEN}✓${NC} pluto installed: $VERSION"
else
    echo -e "${RED}✗${NC} pluto not installed"
    ALL_INSTALLED=false
fi

echo ""

if $ALL_INSTALLED; then
    echo -e "${GREEN}All required tools are installed!${NC}"
    exit 0
else
    echo -e "${YELLOW}Some tools are missing. See references/installation.md for installation instructions.${NC}"
    exit 1
fi
