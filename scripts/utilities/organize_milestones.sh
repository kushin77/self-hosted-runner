#!/usr/bin/env bash
set -euo pipefail

# organize_milestones.sh
# Preview or apply automated milestone creation and assignment using the `gh` CLI.
# Defaults to preview mode. Pass --apply to perform changes.

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "kushin77/self-hosted-runner")"
DRY_RUN=1
if [ "${1:-}" = "--apply" ]; then
  DRY_RUN=0
fi

echo "Repo: $REPO"
echo "Mode: $([ $DRY_RUN -eq 1 ] && echo preview || echo apply)"

MILESTONES=(
  "Observability & Provisioning|Provision agents, configure log/metric pipelines, validate observability."
  "Secrets & Credential Management|GSM/Vault/AWS Secrets provisioning, rotation, and access."
  "Deployment Automation & Migration|Canary runs, migration verification, and deployment safety checks."
  "Governance & CI Enforcement|Branch protection, validation/enforcement workflows, and governance gaps."
  "Documentation & Runbooks|Consolidate operator guides, runbooks, and docs for operators."
  "Monitoring, Alerts & Post-Deploy Validation|Validate metrics/log ingestion, alerts, and post-deploy checks."
)

echo "\nProposed milestones:"
for m in "${MILESTONES[@]}"; do
  IFS='|' read -r title desc <<< "$m"
  printf "- %s: %s\n" "$title" "$desc"
done

if [ $DRY_RUN -eq 1 ]; then
  echo "\nPreview only: no changes will be made. To apply, run: $0 --apply"
fi

# create missing milestones
for m in "${MILESTONES[@]}"; do
  IFS='|' read -r title desc <<< "$m"
  if [ $DRY_RUN -eq 1 ]; then
    echo "Would create milestone: $title"
  else
    echo "Creating milestone: $title"
    gh api repos/$REPO/milestones -f title="$title" -f description="$desc" || true
  fi
done

# dump open issues
TMP=/tmp/organize_milestones_$$.json
gh issue list --state open --limit 1000 --json number,title,body,labels,milestone > "$TMP"

echo "\nBuilding heuristic mapping and assignment plan..."
python3 - <<'PY'
import json,sys
issues=json.load(open('$TMP'))
groups={
 'Observability & Provisioning':['observab','provision','agent','filebeat','node_exporter','vault-agent','provisioning'],
 'Secrets & Credential Management':['secret','secrets','aws','secretsmanager','gsm','vault','kms','credential','gitleaks','secrets found','rotate'],
 'Deployment Automation & Migration':['deploy','deployment','canary','migration','terraform','wrapper','idempotent','terraform'],
 'Governance & CI Enforcement':['governance','branch','protection','ci','workflow','enforce','validation','policy','pr','main','enforcement'],
 'Documentation & Runbooks':['doc','docs','runbook','guide','readme','documentation'],
 'Monitoring, Alerts & Post-Deploy Validation':['monitor','alert','prometheus','ingest','log','logging','alerting','metric']
}
plan={g:[] for g in groups}
unassigned=[]
for i in issues:
    if i.get('milestone'):
        continue
    text=(i.get('title') or '')+"\n"+(i.get('body') or '')
    t=text.lower()
    best=None
    bestscore=0
    for g,keys in groups.items():
        score=0
        for k in keys:
            if k in t:
                score+=1
        if score>bestscore:
            best=g; bestscore=score
    if best:
        plan[best].append(i['number'])
    else:
        unassigned.append(i['number'])

print('Planned assignments:')
for g,ids in plan.items():
    print(f'- {g}: {len(ids)}')
print(f'- All Untriaged (fallback): {len(unassigned)}')
print('\nSample per group (top 10):')
for g,ids in plan.items():
    print(f'-- {g}:', ids[:10])
print('-- All Untriaged sample:', unassigned[:20])
print('\nTo apply these changes, re-run the wrapper with --apply')
PY

if [ $DRY_RUN -eq 1 ]; then
  echo "\nPreview complete. No changes made."
  rm -f "$TMP"
  exit 0
fi

echo "Applying assignments in batches..."
# Assign by repeating the same heuristic in shell to call gh
python3 - <<'PY'
import json,subprocess
issues=json.load(open('$TMP'))
groups={
 'Observability & Provisioning':['observab','provision','agent','filebeat','node_exporter','vault-agent','provisioning'],
 'Secrets & Credential Management':['secret','secrets','aws','secretsmanager','gsm','vault','kms','credential','gitleaks','secrets found','rotate'],
 'Deployment Automation & Migration':['deploy','deployment','canary','migration','terraform','wrapper','idempotent','terraform'],
 'Governance & CI Enforcement':['governance','branch','protection','ci','workflow','enforce','validation','policy','pr','main','enforcement'],
 'Documentation & Runbooks':['doc','docs','runbook','guide','readme','documentation'],
 'Monitoring, Alerts & Post-Deploy Validation':['monitor','alert','prometheus','ingest','log','logging','alerting','metric']
}
def pick(text):
    t=text.lower()
    best=None; bestscore=0
    for g,keys in groups.items():
        score=sum(1 for k in keys if k in t)
        if score>bestscore:
            best=g; bestscore=score
    return best

assigned=0; failed=[]
for i in issues:
    if i.get('milestone'):
        continue
    num=i['number']; text=(i.get('title') or '')+'\n'+(i.get('body') or '')
    g=pick(text)
    target=g if g else 'All Untriaged'
    # attempt assign
    r=subprocess.run(['gh','issue','edit',str(num),'--milestone',target], capture_output=True, text=True)
    if r.returncode==0:
        assigned+=1
    else:
        failed.append({'issue':num,'err':r.stderr})
print('Assigned',assigned,'failed',len(failed))
if failed:
    print('Sample failures:', failed[:10])
PY

echo "Done. Cleaning up."
rm -f "$TMP"
