#!/bin/bash
# Disable all workflows except core infrastructure
for f in .github/workflows/*.yml; do
    name=$(basename "$f")
    # Keep only these critical workflows
    if [[ "$name" =~ ^(preflight|00-master|test\.yml|build\.yml|security\.yml)$ ]]; then
        echo "  KEEP: $name"
    else
        echo "  DISABLE: $name"
        mv "$f" "${f}.disabled"
    fi
done
