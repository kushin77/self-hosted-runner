#!/usr/bin/env bash
set -euo pipefail

# Exchange a third-party OIDC token for a Google access token, then
# call IAM Credentials API to generate a short-lived service account token.
#
# Usage:
#  SUBJECT_TOKEN="..." PROJECT_NUMBER=1234567890 WI_POOL=runner-pool WI_PROVIDER=runner-provider \
#    SA_EMAIL=nxs-automation-sa@nexusshield-prod.iam.gserviceaccount.com SCOPES="https://www.googleapis.com/auth/cloud-platform" \
#    ./exchange-wi-token.sh --print-token

SUBJECT_TOKEN="${SUBJECT_TOKEN:-}"      # OIDC JWT (required)
PROJECT_NUMBER="${PROJECT_NUMBER:-}"    # numeric project number (required)
WI_POOL="${WI_POOL:-}"                  # workload identity pool id (required)
WI_PROVIDER="${WI_PROVIDER:-}"          # provider id (required)
SA_EMAIL="${SA_EMAIL:-}"                # target service account email (required)
SCOPES="${SCOPES:-https://www.googleapis.com/auth/cloud-platform}"

print_token=false
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --print-token) print_token=true; shift ;;
    --subject-token) SUBJECT_TOKEN="$2"; shift 2 ;;
    --project-number) PROJECT_NUMBER="$2"; shift 2 ;;
    --wi-pool) WI_POOL="$2"; shift 2 ;;
    --wi-provider) WI_PROVIDER="$2"; shift 2 ;;
    --sa-email) SA_EMAIL="$2"; shift 2 ;;
    --scopes) SCOPES="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$SUBJECT_TOKEN" ] || [ -z "$PROJECT_NUMBER" ] || [ -z "$WI_POOL" ] || [ -z "$WI_PROVIDER" ] || [ -z "$SA_EMAIL" ]; then
  echo "Missing required env/args. Provide SUBJECT_TOKEN, PROJECT_NUMBER, WI_POOL, WI_PROVIDER, SA_EMAIL." >&2
  exit 2
fi

STS_ENDPOINT="https://sts.googleapis.com/v1/token"
AUDIENCE="//iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WI_POOL}/providers/${WI_PROVIDER}"

response=$(curl -sS -X POST "$STS_ENDPOINT" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=urn:ietf:params:oauth:grant-type:token-exchange" \
  --data-urlencode "audience=${AUDIENCE}" \
  --data-urlencode "requested_token_type=urn:ietf:params:oauth:token-type:access_token" \
  --data-urlencode "subject_token_type=urn:ietf:params:oauth:token-type:jwt" \
  --data-urlencode "subject_token=${SUBJECT_TOKEN}")

access_token=$(echo "$response" | jq -r .access_token // empty)
if [ -z "$access_token" ]; then
  echo "Failed to exchange subject token for access token: $response" >&2
  exit 3
fi

# Now call IAM Credentials API to generate a short-lived service account access token
IAMC_ENDPOINT="https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${SA_EMAIL}:generateAccessToken"
scopes_json=$(printf '%s' "$SCOPES" | awk -v RS=' ' '{print "\"" $0 "\""}' | paste -sd, -)
body="{\"scope\":[${scopes_json}] }"

iam_resp=$(curl -sS -X POST "$IAMC_ENDPOINT" \
  -H "Authorization: Bearer ${access_token}" \
  -H "Content-Type: application/json" \
  -d "$body")

sa_token=$(echo "$iam_resp" | jq -r .accessToken // empty)
if [ -z "$sa_token" ]; then
  echo "Failed to generate service account token: $iam_resp" >&2
  exit 4
fi

expiry=$(echo "$iam_resp" | jq -r .expireTime // empty)

if [ "$print_token" = true ]; then
  echo "$sa_token"
  exit 0
fi

# Print JSON with token and expiry for callers
jq -n --arg token "$sa_token" --arg expiry "$expiry" '{access_token:$token,expire_time:$expiry}'
