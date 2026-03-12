#!/usr/bin/env bash
set -euo pipefail

# organize_milestones.sh
# Preview or apply automated milestone creation and assignment using the `gh` CLI.
# Defaults to preview mode. Pass --apply to perform changes.

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "kushin77/self-hosted-runner")"
DRY_RUN=1
ISSUE_STATE=open
MIN_SCORE=${MIN_SCORE:-2}
REASSIGN=${REASSIGN:-0}
FAILURE_THRESHOLD=${FAILURE_THRESHOLD:-10}
for arg in "$@"; do
  case "$arg" in
    --apply) DRY_RUN=0 ;;
    --closed) ISSUE_STATE=closed ;;
  esac
done

echo "Repo: $REPO"
echo "Mode: $([ $DRY_RUN -eq 1 ] && echo preview || echo apply)"
echo "Issue state: $ISSUE_STATE"

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
  printf '%s\n' "- $title: $desc"
done

if [ $DRY_RUN -eq 1 ]; then
  echo "\nPreview only: no changes will be made. To apply, run: $0 --apply"
fi

# create missing milestones
for m in "${MILESTONES[@]}"; do
  IFS='|' read -r title desc <<< "$m"
  exists=$(gh api repos/$REPO/milestones --jq ".[] | select(.title==\"$title\") | .number" 2>/dev/null || true)
  if [ -n "$exists" ]; then
    echo "Milestone exists: $title"
    continue
  fi
  if [ $DRY_RUN -eq 1 ]; then
    echo "Would create milestone: $title"
  else
    echo "Creating milestone: $title"
    gh api repos/$REPO/milestones -f title="$title" -f description="$desc" || true
  fi
done

# dump open issues
TMP=$(mktemp /tmp/organize_milestones_XXXX.json)
gh issue list --state "$ISSUE_STATE" --limit 1000 --json number,title,body,labels,milestone > "$TMP"

echo "\nBuilding heuristic mapping and assignment plan..."
python3 - <<PY
import json,sys,os
issues=json.load(open("$TMP"))
MIN_SCORE=int(os.getenv('MIN_SCORE', '2'))
groups={
 'Observability & Provisioning':['observab','provision','agent','filebeat','node_exporter','vault-agent','provisioning'],
 'Secrets & Credential Management':['secret','secrets','aws','secretsmanager','gsm','vault','kms','credential','gitleaks','secrets found','rotate'],
 'Deployment Automation & Migration':['deploy','deployment','canary','migration','terraform','wrapper','idempotent','terraform'],
 'Governance & CI Enforcement':['governance','branch','protection','ci','workflow','enforce','validation','policy','pr','main','enforcement'],
 'Documentation & Runbooks':['doc','docs','runbook','guide','readme','documentation'],
 'Monitoring, Alerts & Post-Deploy Validation':['monitor','alert','prometheus','ingest','log','logging','alerting','metric']
}
label_map={
  'area:observability':'Observability & Provisioning',
  'area:secrets':'Secrets & Credential Management',
  'area:deployment':'Deployment Automation & Migration',
  'area:governance':'Governance & CI Enforcement',
  'area:docs':'Documentation & Runbooks',
  'area:monitoring':'Monitoring, Alerts & Post-Deploy Validation'
}

def pick(text, labels):
  t=(text or '').lower()
  # label-first mapping
  for L in labels:
    if L.lower() in label_map:
      return label_map[L.lower()], 999
  scores={}
  for g,keys in groups.items():
    scores[g]=sum(1 for k in keys if k in t)
  bestscore=max(scores.values()) if scores else 0
  if bestscore<MIN_SCORE:
    return None, bestscore
  candidates=[g for g,s in scores.items() if s==bestscore]
  return (candidates[0], bestscore) if candidates else (None,0)

plan={g:[] for g in groups}
unassigned=[]
confidence_counts={}
for i in issues:
  if i.get('milestone'):
    continue
  text=(i.get('title') or '')+'\n'+(i.get('body') or '')
  labels=[l['name'] for l in i.get('labels',[])]
  g,score=pick(text, labels)
  if g:
    plan[g].append((i['number'],score))
    confidence_counts.setdefault(score,0); confidence_counts[score]+=1
  else:
    unassigned.append(i['number'])

print('Planned assignments:')
for g,ids in plan.items():
  print(f'- {g}: {len(ids)}')
print(f'- All Untriaged (fallback): {len(unassigned)}')
print('\nConfidence distribution:')
for s,c in sorted(confidence_counts.items(), reverse=True):
  print(f'- score {s}: {c}')
print('\nSample per group (top 10):')
for g,ids in plan.items():
  print(f'-- {g}:', [i for i,s in ids[:10]])
print('-- All Untriaged sample:', unassigned[:20])
print('\nTo apply these changes, re-run the wrapper with --apply')
PY

if [ $DRY_RUN -eq 1 ]; then
  echo "\nPreview complete. No changes made."
  rm -f "$TMP"
  exit 0
fi

echo "Applying assignments in batches..."
# Assign by repeating the heuristic in Python; track failures and abort if too many
python3 - <<PY
import json,subprocess,os
issues=json.load(open("$TMP"))
MIN_SCORE=int(os.getenv('MIN_SCORE','2'))
FAILURE_THRESHOLD=int(os.getenv('FAILURE_THRESHOLD','10'))
groups={
 'Observability & Provisioning':['observab','provision','agent','filebeat','node_exporter','vault-agent','provisioning'],
 'Secrets & Credential Management':['secret','secrets','aws','secretsmanager','gsm','vault','kms','credential','gitleaks','secrets found','rotate'],
 'Deployment Automation & Migration':['deploy','deployment','canary','migration','terraform','wrapper','idempotent','terraform'],
 'Governance & CI Enforcement':['governance','branch','protection','ci','workflow','enforce','validation','policy','pr','main','enforcement'],
 'Documentation & Runbooks':['doc','docs','runbook','guide','readme','documentation'],
 'Monitoring, Alerts & Post-Deploy Validation':['monitor','alert','prometheus','ingest','log','logging','alerting','metric']
}
label_map={
  'area:observability':'Observability & Provisioning',
  'area:secrets':'Secrets & Credential Management',
  'area:deployment':'Deployment Automation & Migration',
  'area:governance':'Governance & CI Enforcement',
  'area:docs':'Documentation & Runbooks',
  'area:monitoring':'Monitoring, Alerts & Post-Deploy Validation'
}

def pick(text, labels):
    t=(text or '').lower()
    for L in labels:
        if L.lower() in label_map:
            return label_map[L.lower()], 999
    scores={}
    for g,keys in groups.items():
        scores[g]=sum(1 for k in keys if k in t)
    bestscore=max(scores.values()) if scores else 0
    if bestscore<MIN_SCORE:
        return None, bestscore
    candidates=[g for g,s in scores.items() if s==bestscore]
    return (candidates[0], bestscore) if candidates else (None,0)

assigned=0; failed=[]
for i in issues:
    if i.get('milestone') and os.getenv('REASSIGN','0')!='1':
        continue
    num=i['number']; text=(i.get('title') or '')+'\n'+(i.get('body') or '')
    labels=[l['name'] for l in i.get('labels',[])]
    g,score=pick(text, labels)
    target=g if g else 'All Untriaged'
    # attempt assign
    r=subprocess.run(['gh','issue','edit',str(num),'--milestone',target], capture_output=True, text=True)
    if r.returncode==0:
        assigned+=1
    else:
        failed.append({'issue':num,'err':r.stderr})
        print('FAILED assign', num, '->', target, 'err:', r.stderr)
    if len(failed)>=FAILURE_THRESHOLD:
        print('Too many failures; aborting')
        break

print('Assigned',assigned,'failed',len(failed))
if failed:
  print('Sample failures:', failed[:10])
  try:
    body='Milestone organizer encountered failures for %d issues. See artifact logs for details.' % len(failed)
    subprocess.run(['gh','issue','create','--title','milestone-organizer: assignment failures','--body',body], check=False)
  except Exception as e:
    print('Failed to create alert issue:', e)
  raise SystemExit(2)
PY

echo "Done. Cleaning up."
rm -f "$TMP"
