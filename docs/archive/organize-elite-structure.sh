#!/bin/bash
set -e

echo "🏗️  ELITE FOLDER ORGANIZATION IN PROGRESS..."

# Archive historical reports (docs/archive/)
echo "📦 Archiving historical reports..."
find . -maxdepth 1 -type f \( \
  -name "DEPLOYMENT_*.md" \
  -o -name "PHASE_*.md" \
  -o -name "PHASE*.md" \
  -o -name "PRODUCTION_*.md" \
  -o -name "MILESTONE_*.md" \
  -o -name "FINAL_*.md" \
  -o -name "EXECUTION_*.md" \
  -o -name "*_FINAL*.md" \
  -o -name "COMPLETE_*.md" \
  -o -name "AUTONOMOUS_*.md" \
  -o -name "OPERATIONAL_*.md" \
  -o -name "*COMPLETION*.md" \
  -o -name "*READINESS*.md" \
  -o -name "*CERTIFICATION*.md" \
  -o -name "ISSUE_*.md" \
  -o -name "*REPORT*.md" \
  -o -name "*SUMMARY*.md" \
  -o -name "*STATUS*.md" \
  -o -name "*HANDOFF*.md" \
  \) -exec mv {} docs/archive/ \;

echo "✅ Archive complete (historical reports moved to docs/archive/)"

# Move governance files to docs/governance/
echo "🔐 Organizing governance files..."
[ -f "GIT_GOVERNANCE_STANDARDS.md" ] && mv "GIT_GOVERNANCE_STANDARDS.md" docs/governance/
[ -f "NO_GITHUB_ACTIONS_POLICY.md" ] && mv "NO_GITHUB_ACTIONS_POLICY.md" docs/governance/
[ -f "REPO_DEPLOYMENT_POLICY.md" ] && mv "REPO_DEPLOYMENT_POLICY.md" docs/governance/

echo "✅ Governance files organized"

# Move deployment guides to docs/deployment/
echo "📚 Organizing deployment documentation..."
[ -f "CREDENTIAL_PROVISIONING_RUNBOOK.md" ] && mv "CREDENTIAL_PROVISIONING_RUNBOOK.md" docs/deployment/
[ -f "AUTOMATED_TRUNK_DEPLOYMENT_GUIDE.md" ] && mv "AUTOMATED_TRUNK_DEPLOYMENT_GUIDE.md" docs/deployment/
[ -f "FAILOVER_TEST_PROCEDURES.md" ] && mv "FAILOVER_TEST_PROCEDURES.md" docs/deployment/
[ -f "README_DEPLOYMENT_SYSTEM.md" ] && mv "README_DEPLOYMENT_SYSTEM.md" docs/deployment/
[ -f "RUN_LOCAL.md" ] && mv "RUN_LOCAL.md" docs/deployment/
[ -f "QUICK_START_COMMANDS.sh" ] && mv "QUICK_START_COMMANDS.sh" scripts/utilities/

echo "✅ Deployment documentation organized"

# Move NexusShield specific docs
echo "🛡️  Organizing NexusShield documentation..."
find . -maxdepth 1 -type f -name "NEXUSSHIELD_*.md" -exec mv {} docs/archive/ \;

echo "✅ NexusShield documentation archived"

# Move observability/monitoring guides to docs/runbooks/
echo "📊 Organizing observability documentation..."
find . -maxdepth 1 -type f \( \
  -name "*OBSERVABILITY*.md" \
  -o -name "*MONITORING*.md" \
  \) -exec mv {} docs/runbooks/ \;

echo "✅ Observability documentation organized"

# Move operational guides/runbooks
echo "📖 Organizing operational runbooks..."
find . -maxdepth 1 -type f \( \
  -name "*RUNBOOK*.md" \
  -o -name "*PLAYBOOK*.md" \
  -o -name "*GUIDE*.md" \
  -o -name "*CHECKLIST*.md" \
  -o -name "*PROCEDURES*.md" \
  \) ! -name "README*" -exec mv {} operations/playbooks/ \;

echo "✅ Operational runbooks organized"

# Move architecture docs
echo "🏛️  Organizing architecture documentation..."
find . -maxdepth 1 -type f \( \
  -name "*ARCHITECTURE*.md" \
  -o -name "*FRAMEWORK*.md" \
  -o -name "*DESIGN*.md" \
  \) -exec mv {} docs/architecture/ \;

echo "✅ Architecture documentation organized"

# Move shell scripts to scripts/ subdirectories
echo "🚀 Organizing scripts..."
# Move existing scripts from scripts root to subdirectories
cd scripts 2>/dev/null || exit 0

# Deployment scripts
find . -maxdepth 1 -type f -name "*.sh" \( \
  -name "*deploy*.sh" \
  -o -name "*apply*.sh" \
  -o -name "*provision*.sh" \
  \) -exec mv {} deployment/ \;

# Provisioning scripts  
find . -maxdepth 1 -type f -name "*.sh" \( \
  -name "*provision*.sh" \
  -o -name "*credential*.sh" \
  -o -name "*secret*.sh" \
  -o -name "*rotate*.sh" \
  \) -exec mv {} provisioning/ \;

# Automation/orchestration scripts
find . -maxdepth 1 -type f -name "*.sh" \( \
  -name "*automat*.sh" \
  -o -name "*orchestrat*.sh" \
  -o -name "*phase*.sh" \
  -o -name "*workflow*.sh" \
  \) -exec mv {} automation/ \;

# Utility/helper scripts
find . -maxdepth 1 -type f \( -name "*.sh" -o -name "*.py" -o -name "*.txt" \) -exec mv {} utilities/ \;

cd ..
echo "✅ Scripts organized into deployment/, provisioning/, automation/, utilities/"

# Move docker-compose files to config/
echo "⚙️  Organizing configuration files..."
find . -maxdepth 1 -type f -name "docker-compose*.yml" -exec mv {} config/ \;
[ -f ".env.example" ] && cp ".env.example" config/
[ -f "staging.kubeconfig" ] && mv "staging.kubeconfig" config/

echo "✅ Configuration files organized"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "✨ ELITE FOLDER ORGANIZATION COMPLETE! ✨"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "Summary:"
echo "  ✅ docs/archive/        - Historical reports"
echo "  ✅ docs/governance/     - Governance standards"
echo "  ✅ docs/deployment/     - Deployment guides"
echo "  ✅ docs/runbooks/       - Operational runbooks"
echo "  ✅ docs/architecture/   - Architecture docs"
echo "  ✅ operations/playbooks/- Operational playbooks"
echo "  ✅ config/              - Configuration files"
echo "  ✅ scripts/**/*         - Organized scripts"
echo ""
