#!/bin/bash
# /usr/local/bin/con-bootstrap-entry
# Runs once on first boot to provision the conspiracy.
set -euo pipefail

echo "ConspiracyOS bootstrap starting..."

# Run the bootstrap
con bootstrap

# Mark as bootstrapped
touch /srv/con/.bootstrapped

echo "ConspiracyOS bootstrap complete."
