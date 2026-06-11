#!/usr/bin/env bash
# Generate SHA256SUMS for a release. Maintainer-only; not part of the tool.
set -eu
cd "$(dirname "$0")"
sha256sum revelio > SHA256SUMS
echo "wrote SHA256SUMS:"
cat SHA256SUMS
