#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LOG_DIR="$ROOT_DIR/terraform-validate-reports"
mkdir -p "$LOG_DIR"

echo "Starting terraform validation across directories..."

RESULT=0
REPORTS=()

for dir in $(find . -maxdepth 3 -type d -name "*" | sed 's|^./||'); do
  # Skip common non-terraform dirs
  case "$dir" in
    .|.github|scripts|docs|ansible|build|artifacts|apps|alerts) continue ;;
  esac
  if compgen -G "$dir/*.tf" > /dev/null; then
    echo "Validating: $dir"
    pushd "$dir" >/dev/null
    mkdir -p .terraform || true
    if terraform init -backend=false >/dev/null 2>&1; then
      if terraform validate >/dev/null 2>&1; then
        echo "VALID: $dir" | tee -a "$LOG_DIR/validate.log"
      else
        echo "INVALID: $dir" | tee -a "$LOG_DIR/validate.log"
        RESULT=2
      fi
    else
      echo "INIT_FAILED: $dir" | tee -a "$LOG_DIR/validate.log"
      RESULT=3
    fi
    REPORTS+=("$dir")
    popd >/dev/null
  fi
done

# Summary
if [[ $RESULT -eq 0 ]]; then
  echo "All validated Terraform modules passed."
else
  echo "Terraform validation found issues. Check $LOG_DIR/validate.log"
fi

exit $RESULT
