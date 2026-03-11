#!/usr/bin/env bash
set -euo pipefail

# governance-scan.sh
# Scans repo tags and recent commits to detect releases created by disallowed actors
# (GitHub Actions, pull-based accounts, bots). Reports findings to an audit issue.
# Usage:
#  GITHUB_TOKEN=<token> ./tools/governance-scan.sh --owner=kushin77 --repo=self-hosted-runner --audit-issue=2619

OWNER=${OWNER:-kushin77}
REPO=${REPO:-self-hosted-runner}
AUDIT_ISSUE=${AUDIT_ISSUE:-2619}
SINCE_DAYS=${SINCE_DAYS:-7}

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "ERROR: GITHUB_TOKEN must be set"
  exit 2
fi

echo "Scanning tags and recent commits for $OWNER/$REPO (since ${SINCE_DAYS}d)"

# Get tags
TAGS_JSON=$(curl -sS -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$OWNER/$REPO/tags?per_page=100")
TAGS=$(echo "$TAGS_JSON" | jq -r '.[].name')

violations=()

for tag in $TAGS; do
  # Fetch tag ref -> commit
  # Try release object first
  rel=$(curl -sS -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$OWNER/$REPO/releases/tags/$tag" || true)
  rel_id=$(echo "$rel" | jq -r '.id // empty')
  if [ -n "$rel_id" ]; then
    # If release exists, check author
    author_login=$(echo "$rel" | jq -r '.author.login // empty')
    if [[ "$author_login" =~ github-actions|dependabot|bot ]]; then
      violations+=("Tag:$tag -> release author:$author_login")
    fi
  else
    # No release; check annotated tag ref commit author
    ref_json=$(curl -sS -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$OWNER/$REPO/git/refs/tags/$tag" || true)
    commit_sha=$(echo "$ref_json" | jq -r '.object.sha // empty')
    if [ -n "$commit_sha" ]; then
      commit=$(curl -sS -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$OWNER/$REPO/commits/$commit_sha" || true)
      author_login=$(echo "$commit" | jq -r '.author.login // empty')
      author_name=$(echo "$commit" | jq -r '.commit.author.name // empty')
      if [[ "$author_login" =~ github-actions|dependabot|bot ]] || [[ "$author_name" =~ "GitHub" ]]; then
        violations+=("Tag:$tag -> commit:$commit_sha author_login:$author_login author_name:$author_name")
      fi
    fi
  fi
done

# Also scan recent commits for 'release' keywords created within SINCE_DAYS
since_date=$(date -d "${SINCE_DAYS} days ago" --utc +"%Y-%m-%dT%H:%M:%SZ")
commits=$(curl -sS -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$OWNER/$REPO/commits?since=$since_date&per_page=100")
for sha in $(echo "$commits" | jq -r '.[].sha'); do
  msg=$(echo "$commits" | jq -r ".[] | select(.sha==\"$sha\") | .commit.message")
  if echo "$msg" | grep -iq "release"; then
    c=$(curl -sS -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$OWNER/$REPO/commits/$sha")
    alogin=$(echo "$c" | jq -r '.author.login // empty')
    aname=$(echo "$c" | jq -r '.commit.author.name // empty')
    if [[ "$alogin" =~ github-actions|dependabot|bot ]] || [[ "$aname" =~ "GitHub" ]]; then
      violations+=("Commit:$sha -> message:$msg author_login:$alogin author_name:$aname")
    fi
  fi
done

if [ ${#violations[@]} -eq 0 ]; then
  echo "No governance violations detected. Posting success note to audit issue #$AUDIT_ISSUE"
  curl -sS -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" "https://api.github.com/repos/$OWNER/$REPO/issues/$AUDIT_ISSUE/comments" -d "{\"body\": \"governance-scan: no violations detected (checked tags and recent commits).\"}"
  exit 0
fi

# Compose report
report="governance-scan: detected potential violations:\n"
for v in "${violations[@]}"; do
  report+="- $v\n"
done

# Post report to audit issue
curl -sS -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" "https://api.github.com/repos/$OWNER/$REPO/issues/$AUDIT_ISSUE/comments" -d "{\"body\": \"$report\"}"

# Create escalation issue for each violation
for v in "${violations[@]}"; do
  title="Escalation: governance violation detected for $REPO"
  body="Automated governance scan detected potential violation:\n\n$v\n\nPlease investigate and remediate. This was automatically reported by tools/governance-scan.sh."
  curl -sS -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" "https://api.github.com/repos/$OWNER/$REPO/issues" -d "{\"title\": \"$title\", \"body\": \"$body\", \"labels\": [\"governance/escalation\"]}"
done

echo "Posted ${#violations[@]} escalation(s) and reported to audit issue #$AUDIT_ISSUE"
