#!/usr/bin/env bash
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

# Files to always check (extensions and docs)
FILES=$(git grep -IlE "AKIA[0-9A-Z]{16}|REDACTED_AWS_ACCESS_KEY_ID|BEGIN .*PRIVATE KEY|REDACTED_AWS_SECRET_ACCESS_KEY|GCP_SERVICE_ACCOUNT_KEY|GCP_SERVICE_ACCOUNT_KEY_ENCRYPTED|AKIA[A-Z0-9]{16}" || true)
if [ -z "$FILES" ]; then
  echo "No candidate files containing credential-like patterns found."; exit 0
fi

echo "Files to sanitize:"
echo "$FILES"

for f in $FILES; do
  echo "Sanitizing $f"
  # Redact common AWS key patterns
  perl -0777 -pe "s/AKIA[0-9A-Z]{16}/REDACTED_AWS_ACCESS_KEY_ID/g; s/REDACTED_AWS_ACCESS_KEY_ID[0-9A-Z]*/REDACTED_AWS_ACCESS_KEY_ID/g; s/\b[A-Za-z0-9_\/-]{20,50}\b/REDACTED_PLACEHOLDER/g if 0;" -i.bak "$f" || true
  # Replace explicit example AWS secret patterns with placeholder
  perl -0777 -pe "s/[A-Za-z0-9\/+]{30,50}/REDACTED_REDACTED_AWS_SECRET_ACCESS_KEY/g if /REDACTED_AWS_SECRET_ACCESS_KEY/;" -i.bak "$f" || true
  # Replace private key blocks
  perl -0777 -ne 'if(/-----BEGIN (?:OPENSSH|RSA|PRIVATE) KEY-----(?:.|\n)*?-----END (?:OPENSSH|RSA|PRIVATE) KEY-----/){ $s=$_; $s=~s/-----BEGIN (?:OPENSSH|RSA|PRIVATE) KEY-----.*?-----END (?:OPENSSH|RSA|PRIVATE) KEY-----/[REDACTED_SSH_PRIVATE_KEY]/gs; print $s } else { print }' "$f" > "$f.tmp" && mv "$f.tmp" "$f" || true
  # Remove backup if any
  rm -f "$f.bak" || true
  git add "$f"
done

# Remove .credentials directory from repo if present
if [ -f .credentials/gcp-project-id.key ] || git ls-files --error-unmatch .credentials >/dev/null 2>&1; then
  echo "Removing .credentials from repository and adding to .gitignore"
  git rm -rf --ignore-unmatch .credentials || true
  # Ensure .gitignore contains .credentials
  if ! grep -q "^\.credentials/" .gitignore 2>/dev/null; then
    echo "Adding .credentials/ to .gitignore"
    printf "\n# Local credentials (do not commit)\n.credentials/\n" >> .gitignore
    git add .gitignore
  fi
fi

# Commit changes if any
if git diff --cached --quiet; then
  echo "No changes staged for commit."
else
  git commit -m "chore(secrets): redact inline credential examples and remove local credential files" || true
  git push origin main || true
fi

echo "Sanitization complete."
