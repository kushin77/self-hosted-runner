#!/usr/bin/env bash
set -euo pipefail

: ${GITLAB_TOKEN:?Need to set GITLAB_TOKEN}
: ${CI_PROJECT_ID:?Need to set CI_PROJECT_ID}
GITLAB_API_URL=${GITLAB_API_URL:-"https://gitlab.com/api/v4"}

echo "=== Triggering First GitLab CI Pipeline (validation) ==="
echo "Project: ${CI_PROJECT_ID}"
echo "API URL: ${GITLAB_API_URL}"
echo ""

# Trigger pipeline on main branch
echo "-> Triggering pipeline on main branch..."
PIPELINE=$(curl -sSL -X POST -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${GITLAB_API_URL}/projects/${CI_PROJECT_ID}/pipeline" \
  -d "ref=main" \
  -w "\n%{http_code}")

HTTP_CODE=$(echo "$PIPELINE" | tail -n1)
RESPONSE=$(echo "$PIPELINE" | head -n-1)

if [ "$HTTP_CODE" != "201" ]; then
  echo "❌ Pipeline trigger failed (HTTP $HTTP_CODE)"
  echo "Response: $RESPONSE"
  exit 1
fi

PIPELINE_ID=$(echo "$RESPONSE" | jq -r '.id')
PIPELINE_URL=$(echo "$RESPONSE" | jq -r '.web_url')

echo "✅ Pipeline triggered successfully"
echo "Pipeline ID: $PIPELINE_ID"
echo "Pipeline URL: $PIPELINE_URL"
echo ""

# Wait for pipeline to start and show status
echo "-> Waiting for pipeline to initialize (up to 30 sec)..."
for i in {1..30}; do
  STATUS=$(curl -sSL -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "${GITLAB_API_URL}/projects/${CI_PROJECT_ID}/pipelines/${PIPELINE_ID}" | jq -r '.status // "unknown"')
  
  if [ "$STATUS" != "unknown" ]; then
    echo "Pipeline status: $STATUS"
    break
  fi
  
  if [ $i -eq 30 ]; then
    echo "⏱️ Pipeline init timeout; check GitLab UI for details"
  fi
  
  sleep 1
done

echo ""
echo "=== Next Steps ==="
echo "1. Open pipeline in browser: $PIPELINE_URL"
echo "2. Wait for 'validate:ci' job to complete (should pass in <1 min)"
echo "3. Manually trigger 'triage:manual' job (click 'Play' button)"
echo "4. Manually trigger 'sla-monitor' job (click 'Play' button)"
echo "5. Verify all jobs passed and issues are labeled"
echo ""
echo "Or check via API:"
echo "curl -sSL -H \"PRIVATE-TOKEN: \$GITLAB_TOKEN\" \\"
echo "  \"${GITLAB_API_URL}/projects/${CI_PROJECT_ID}/pipelines/${PIPELINE_ID}/jobs\" | jq"
