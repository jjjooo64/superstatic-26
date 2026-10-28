#!/bin/bash
set -euo pipefail

# Run from nosecret/aws/install/
# Fixes Windows CRLF line endings and sets execute permissions
# on scripts in this directory.

echo "Fixing Windows line endings..."
find . -type f \( \
  -name "*.sh" -o \
  -name "*.py" -o \
  -name "*.yaml" -o \
  -name "*.json" \
  \) -exec sed -i 's/\r$//' {} \;

echo "Setting execute permissions..."
find . -type f -name "*.sh" -exec chmod +x {} \;
find . -type f -name "*.py" -exec chmod +x {} \;

echo "prep4x complete."
