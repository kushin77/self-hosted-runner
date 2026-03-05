#!/usr/bin/env bash
set -euo pipefail

# Run Terraform plan locally for aws-spot example and produce human-readable plan
# Usage: scripts/local/run-plan.sh [path-to-example]

EXAMPLE_DIR=${1:-terraform/examples/aws-spot}
echo "Running terraform plan in $EXAMPLE_DIR"
pushd "$EXAMPLE_DIR" > /dev/null

terraform init -input=false
terraform validate
terraform plan -out=tfplan -input=false
terraform show -no-color tfplan > aws-spot.plan.txt

echo "Plan written to $EXAMPLE_DIR/aws-spot.plan.txt"
popd > /dev/null

echo "Done."
