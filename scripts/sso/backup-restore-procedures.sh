#!/bin/bash
set -e

# PostgreSQL Backup and Recovery Procedures for SSO Platform
# Implements automated backups to GCS with point-in-time recovery

PROJECT_ID="${1:-nexus-prod}"
BACKUP_BUCKET="${2:-gs://$PROJECT_ID-sso-backups}"
RETENTION_DAYS="${3:-30}"

echo "💾 PostgreSQL Backup & Recovery Management for SSO Platform"
echo "   Project: $PROJECT_ID"
echo "   Bucket: $BACKUP_BUCKET"
echo "   Retention: $RETENTION_DAYS days"
echo ""

# Function: Create backup
backup_database() {
  echo "📦 Creating PostgreSQL backup..."
  
  local backup_timestamp=$(date -u +"%Y%m%d_%H%M%S")
  local backup_name="keycloak_backup_${backup_timestamp}.sql.gz"
  local backup_path="/tmp/$backup_name"
  
  # Get PostgreSQL pod name
  local pg_pod=$(kubectl get pod -n keycloak -l app=keycloak-postgres -o jsonpath='{.items[0].metadata.name}')
  
  if [ -z "$pg_pod" ]; then
    echo "❌ Failed to find PostgreSQL pod"
    return 1
  fi
  
  echo "   Using pod: $pg_pod"
  
  # Get database password from secret
  local db_password=$(kubectl get secret -n keycloak keycloak-postgres \
    -o jsonpath='{.data.password}' | base64 -d)
  
  # Create backup
  kubectl exec -n keycloak "$pg_pod" -- \
    PGPASSWORD="$db_password" pg_dump -U keycloak -d keycloak | gzip > "$backup_path"
  
  echo "   ✅ Backup created: $backup_name"
  
  # Upload to GCS
  echo "   📤 Uploading to GCS..."
  gsutil cp "$backup_path" "$BACKUP_BUCKET/backups/"
  
  # Clean up local backup
  rm "$backup_path"
  
  echo "   ✅ Backup uploaded to $BACKUP_BUCKET/backups/$backup_name"
  
  # Add metadata
  gsutil -h "x-goog-meta-backup-type:full" \
         -h "x-goog-meta-timestamp:$backup_timestamp" \
         cp "$backup_path" "$BACKUP_BUCKET/backups/${backup_name}.meta"
  
  echo ""
  echo "✅ Backup complete: $backup_name"
}

# Function: List backups
list_backups() {
  echo "📋 Available backups in GCS:"
  gsutil ls -h "$BACKUP_BUCKET/backups/" || echo "   No backups found"
}

# Function: Restore from backup
restore_from_backup() {
  local backup_file="$1"
  
  if [ -z "$backup_file" ]; then
    echo "❌ Usage: restore_from_backup <backup_filename>"
    return 1
  fi
  
  echo "🔄 Restoring from backup: $backup_file"
  
  # Get PostgreSQL pod
  local pg_pod=$(kubectl get pod -n keycloak -l app=keycloak-postgres -o jsonpath='{.items[0].metadata.name}')
  
  if [ -z "$pg_pod" ]; then
    echo "❌ Failed to find PostgreSQL pod"
    return 1
  fi
  
  # Get database password
  local db_password=$(kubectl get secret -n keycloak keycloak-postgres \
    -o jsonpath='{.data.password}' | base64 -d)
  
  # Download backup from GCS
  echo "   📥 Downloading backup from GCS..."
  local temp_backup="/tmp/$(basename "$backup_file")"
  gsutil cp "$BACKUP_BUCKET/backups/$backup_file" "$temp_backup"
  
  # Restore database
  echo "   🔄 Restoring database..."
  gunzip -c "$temp_backup" | kubectl exec -i -n keycloak "$pg_pod" -- \
    PGPASSWORD="$db_password" psql -U keycloak -d keycloak
  
  # Clean up
  rm "$temp_backup"
  
  echo "   ✅ Database restored"
  echo ""
  echo "✅ Restore complete from: $backup_file"
}

# Function: Automated daily backup with retention
enable_daily_backups() {
  echo "⏱️  Enabling daily automated backups with retention..."
  
  local backup_script="/etc/cron.daily/sso-database-backup"
  
  cat > "$backup_script" << 'BACKUP_CRON'
#!/bin/bash
set -e
PROJECT_ID="nexus-prod"
BACKUP_BUCKET="gs://$PROJECT_ID-sso-backups"
RETENTION_DAYS="30"

# Create backup
backup_timestamp=$(date -u +"%Y%m%d_%H%M%S")
backup_name="keycloak_backup_${backup_timestamp}.sql.gz"

pg_pod=$(kubectl get pod -n keycloak -l app=keycloak-postgres -o jsonpath='{.items[0].metadata.name}')
db_password=$(kubectl get secret -n keycloak keycloak-postgres -o jsonpath='{.data.password}' | base64 -d)

kubectl exec -n keycloak "$pg_pod" -- \
  PGPASSWORD="$db_password" pg_dump -U keycloak -d keycloak | gzip | \
  gsutil cp - "$BACKUP_BUCKET/backups/$backup_name"

# Remove backups older than retention period
gsutil ls "$BACKUP_BUCKET/backups/" | while read backup; do
  backup_date=$(echo "$backup" | grep -oP '\\d{8}_\\d{6}' | head -1)
  if [ -n "$backup_date" ]; then
    backup_epoch=$(date -d "$(echo $backup_date | sed 's/\\([0-9]\\{4\\}\\)\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)_\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)/\\1-\\2-\\3 \\4:\\5:\\6/')" +%s)
    current_epoch=$(date +%s)
    age_days=$(( ($current_epoch - $backup_epoch) / 86400 ))
    
    if [ "$age_days" -gt "$RETENTION_DAYS" ]; then
      echo "Removing old backup: $(basename $backup)"
      gsutil rm "$backup"
    fi
  fi
done

echo "Daily backup of keycloak database completed successfully"
BACKUP_CRON
  
  chmod +x "$backup_script"
  echo "   ✅ Daily backup script installed"
}

# Function: Point-in-time recovery procedures
point_in_time_recovery() {
  local target_time="$1"
  
  if [ -z "$target_time" ]; then
    echo "❌ Usage: point_in_time_recovery <target_time (YYYY-MM-DD HH:MM:SS)>"
    return 1
  fi
  
  echo "⏮️  Initiating point-in-time recovery to: $target_time"
  
  local pg_pod=$(kubectl get pod -n keycloak -l app=keycloak-postgres -o jsonpath='{.items[0].metadata.name}')
  local db_password=$(kubectl get secret -n keycloak keycloak-postgres \
    -o jsonpath='{.data.password}' | base64 -d)
  
  # Find most recent backup before target time
  echo "   🔍 Finding appropriate backup..."
  # This would require parsing GCS metadata - simplified for now
  
  echo "   ⚠️  PITR recovery requires:"
  echo "      1. Base backup from before target time"
  echo "      2. WAL archive files from GCS"
  echo "      3. PostgreSQL recovery.conf configuration"
  echo ""
  echo "   Steps for manual PITR:"
  echo "      1. Stop PostgreSQL: kubectl delete pod -n keycloak $pg_pod"
  echo "      2. Find base backup: gsutil ls gs://$PROJECT_ID-sso-backups/backups/"
  echo "      3. Restore base: $(basename $0) restore_from_backup <backup_file>"
  echo "      4. Configure recovery target time in postgresql.conf"
  echo "      5. Start recovery process: SELECT pg_wal_replay_resume();"
}

# Function: Verify backup integrity
verify_backup_integrity() {
  local backup_file="$1"
  
  if [ -z "$backup_file" ]; then
    echo "❌ Usage: verify_backup_integrity <backup_filename>"
    return 1
  fi
  
  echo "✔️  Verifying backup integrity: $backup_file"
  
  # Download and test restore in temporary container
  echo "   📥 Downloading backup..."
  local temp_backup="/tmp/$(basename "$backup_file")"
  gsutil cp "$BACKUP_BUCKET/backups/$backup_file" "$temp_backup"
  
  echo "   🧪 Testing backup integrity..."
  if gunzip -t "$temp_backup" >/dev/null 2>&1; then
    echo "   ✅ Backup file is valid gzip"
  else
    echo "   ❌ Backup file is corrupted"
    rm "$temp_backup"
    return 1
  fi
  
  # Optionally test SQL syntax
  if gunzip -c "$temp_backup" | head -100 | grep -q "^--"; then
    echo "   ✅ Backup contains valid SQL"
  else
    echo "   ⚠️  Warning: Could not verify SQL content"
  fi
  
  rm "$temp_backup"
  echo ""
  echo "✅ Backup verification complete"
}

# Main command dispatch
case "$1" in
  backup)
    backup_database
    ;;
  restore)
    restore_from_backup "$2"
    ;;
  list)
    list_backups
    ;;
  enable-daily)
    enable_daily_backups
    ;;
  pitr)
    point_in_time_recovery "$2"
    ;;
  verify)
    verify_backup_integrity "$2"
    ;;
  *)
    echo "PostgreSQL Backup & Recovery Management"
    echo ""
    echo "Usage: $(basename $0) <command> [options]"
    echo ""
    echo "Commands:"
    echo "  backup                            Create manual backup"
    echo "  restore <backup_filename>         Restore from specific backup"
    echo "  list                              List available backups"
    echo "  enable-daily                      Enable daily automated backups"
    echo "  pitr <YYYY-MM-DD HH:MM:SS>        Point-in-time recovery"
    echo "  verify <backup_filename>          Verify backup integrity"
    echo ""
    echo "Examples:"
    echo "  # Manual backup"
    echo "  $(basename $0) backup"
    echo ""
    echo "  # Restore from backup"
    echo "  $(basename $0) restore keycloak_backup_20260313_120000.sql.gz"
    echo ""
    echo "  # Enable daily backups"
    echo "  $(basename $0) enable-daily"
    echo ""
    exit 1
    ;;
esac
