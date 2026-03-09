#!/usr/bin/env bash
set -euo pipefail
# Clean up the generated inventory to produce a minimal valid JSON with repo_secrets only.
INV="${1:-secrets-inventory-$(date -u +%Y-%m-%d).json}"
OUT="${2:-secrets-inventory-clean-$(date -u +%Y-%m-%d).json}"
if [ ! -f "$INV" ]; then
  echo "Inventory $INV not found" >&2
  exit 2
fi

names=()
while IFS= read -r line; do
  if echo "$line" | grep -q '"name"'; then
    n=$(echo "$line" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p')
    names+=("$n")
  fi
done < "$INV"

echo "{" > "$OUT"
echo "  \"generated_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"," >> "$OUT"
echo "  \"repo_secrets\": [" >> "$OUT"
for i in "${!names[@]}"; do
  if [ $i -gt 0 ]; then
    printf ',\n' >> "$OUT"
  else
    printf '\n' >> "$OUT"
  fi
  printf '    {"name": "%s"}' "${names[$i]}" >> "$OUT"
done
printf '\n  ]\n}\n' >> "$OUT"

echo "Wrote cleaned inventory to $OUT"
