set -euo pipefail

OWNER="kushin77"
REPO="self-hosted-runner"
TITLE=""
BODY=""

PAYLOAD={"title":"\"\"","body":"\"{\"owner\":\"kushin77\",\"repo\":\"self-hosted-runner\",\"frequency\":\"weekly\"}\""}

curl -sS -X POST   -H "Authorization: Bearer "   -H "Accept: application/vnd.github+json"   "https://api.github.com/repos///issues"   -d @- <<< "" | jq -c .
