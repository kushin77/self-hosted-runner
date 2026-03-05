#!/usr/bin/env bash
set -euo pipefail

# Apply a previously generated terraform plan locally.
# Usage: scripts/local/run-apply.sh [path-to-example]

EXAMPLE_DIR=${1:-terraform/examples/aws-spot}
echo "Applying terraform plan in $EXAMPLE_DIR"
pushd "$EXAMPLE_DIR" > /dev/null

if [ ! -f tfplan ]; then
  echo "No tfplan found. Run scripts/local/run-plan.sh first to create tfplan." >&2
  exit 2
fi

terraform apply -input=false -auto-approve tfplan

echo "Apply completed."
popd > /dev/null
