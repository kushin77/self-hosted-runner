#!/bin/bash

################################################################################
# SETUP: GitHub Token for NEXUS Phases 3-6
#
# This script:
# 1. Tries to use existing GitHub CLI auth (gh)
# 2. Creates token in Secret Manager if not exists
# 3. Sets up environment for full automation
#
################################################################################

PROJECT_ID="nexusshield-prod"

echo "Setting up GitHub token for NEXUS automation..."
echo ""

# Try Option 1: GitHub CLI (if installed and authenticated)
if command -v gh &> /dev/null; then
    echo "✅ GitHub CLI (gh) detected"
    
    if gh auth status &> /dev/null; then
        echo "✅ GitHub CLI authenticated"
        
        # Get token from gh CLI
        TOKEN=$(gh auth token 2>/dev/null || echo "")
        
        if [ -n "$TOKEN" ]; then
            echo "✅ Token retrieved from GitHub CLI"
            export GITHUB_TOKEN="$TOKEN"
            
            # Store in Secret Manager for future use
            echo "$TOKEN" | gcloud secrets create github-token --data-file=- --project="$PROJECT_ID" 2>/dev/null || \
            echo "$TOKEN" | gcloud secrets versions add github-token --data-file=- --project="$PROJECT_ID" 2>/dev/null || true
            
            echo ""
            echo "✅ GitHub token configured"
            echo "export GITHUB_TOKEN=\"$TOKEN\""
            exit 0
        fi
    fi
fi

# Try Option 2: Check Secret Manager
echo "Checking Secret Manager..."
TOKEN=$(gcloud secrets versions access latest --secret="github-token" --project="$PROJECT_ID" 2>/dev/null || echo "")

if [ -n "$TOKEN" ]; then
    echo "✅ Token found in Secret Manager"
    export GITHUB_TOKEN="$TOKEN"
    
    echo ""
    echo "✅ GitHub token configured from Secret Manager"
    echo "export GITHUB_TOKEN=\"$TOKEN\""
    exit 0
fi

# If no token found, provide instructions
echo "❌ GitHub token not found"
echo ""
echo "Setup options:"
echo ""
echo "1️⃣ Create personal access token:"
echo "   - Go: https://github.com/settings/tokens"
echo "   - Click 'Generate new token (classic)'"
echo "   - Select scopes: repo (full control), admin:repo_hook"
echo "   - Copy token"
echo ""
echo "2️⃣ Store token in Secret Manager:"
echo "   gcloud secrets create github-token --data-file=- --project=$PROJECT_ID"
echo "   (Paste token, then Ctrl+D)"
echo ""
echo "3️⃣ Or set environment variable:"
echo "   export GITHUB_TOKEN=<your-token>"
echo ""
echo "Then run:"
echo "   bash scripts/phases-3-6-full-automation.sh"
echo ""

exit 1
