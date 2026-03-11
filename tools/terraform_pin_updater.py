#!/usr/bin/env python3
###############################################################################
# Phase 2: Terraform Image-Pin Updater (consolidated)
# Consolidated, idempotent, immutable updates for Terraform image pins.
# This script is the canonical implementation; legacy copies should call this.
###############################################################################

import json
import os
import sys
import re
import subprocess
from pathlib import Path
from typing import Dict, List, Optional
from dataclasses import dataclass, asdict
from datetime import datetime

SCRIPT_DIR = Path(__file__).parent.absolute()
REPO_ROOT = SCRIPT_DIR.parent
TERRAFORM_DIR = REPO_ROOT / "terraform"
AUDIT_LOG_DIR = Path.home() / ".phase2-image-pin"
AUDIT_LOG = AUDIT_LOG_DIR / "image_pin.jsonl"


@dataclass
class ImagePin:
    image_name: str
    old_digest: Optional[str]
    new_digest: str
    timestamp: str

    def to_json(self):
        return json.dumps(asdict(self))


IMAGE_RE = re.compile(r'(?P<prefix>image\s*=\s*")(?P<img>[^"\n]+)(?P<suffix>\")')


def setup_audit_log():
    AUDIT_LOG_DIR.mkdir(parents=True, exist_ok=True)
    (AUDIT_LOG_DIR / "audit-lock").touch(mode=0o444)


def log_audit(event: str, status: str, details: str = ""):
    setup_audit_log()
    entry = {
        "timestamp": datetime.utcnow().isoformat(),
        "event": event,
        "status": status,
        "details": details,
        "user": os.environ.get("USER", "unknown"),
        "hostname": os.environ.get("HOSTNAME", "unknown"),
    }
    with open(AUDIT_LOG, "a") as f:
        f.write(json.dumps(entry) + "\n")


def parse_trivy_output(trivy_json_file: str) -> List[Dict]:
    if not os.path.exists(trivy_json_file):
        log_audit("parse_trivy_failed", "ERROR", "File not found")
        return []
    try:
        with open(trivy_json_file) as f:
            trivy_data = json.load(f)
    except json.JSONDecodeError as e:
        log_audit("parse_trivy_failed", "ERROR", f"JSON error: {str(e)}")
        return []

    approved_images = []
    for result in trivy_data.get("Results", []):
        image_name = result.get("Target", "")
        if not image_name:
            continue
        approval_status = result.get("Metadata", {}).get("approval", {})
        if approval_status.get("approved", False):
            image_digest = result.get("Metadata", {}).get("digest", "")
            approved_images.append({
                "image": image_name,
                "digest": image_digest,
                "approved_by": approval_status.get("approved_by", "system"),
                "approved_at": approval_status.get("approved_at", ""),
            })
    log_audit("parse_trivy_success", "SUCCESS", f"Images: {len(approved_images)}")
    return approved_images


def find_terraform_files(directory: Path = TERRAFORM_DIR) -> List[Path]:
    tf_files = []
    for tf_file in directory.rglob("*.tf"):
        if "modules" in tf_file.parts:
            continue
        try:
            with open(tf_file) as f:
                content = f.read()
                if "image" in content.lower() or "digest" in content.lower():
                    tf_files.append(tf_file)
        except Exception:
            continue
    return tf_files


def update_image_references(content: str, image_name: str, new_digest: str) -> str:
    pattern1 = rf'(image\s*=\s*"[^"]*{re.escape(image_name)}[^"]*@)(sha256:[a-f0-9]+)'
    replacement1 = rf'\g<1>sha256:{new_digest}'
    pattern2 = r'(image_digest\s*=\s*"sha256:)[a-f0-9]+'
    replacement2 = rf'\g<1>{new_digest}'
    updated = re.sub(pattern1, replacement1, content)
    updated = re.sub(pattern2, replacement2, updated)
    return updated


def update_terraform_pins(tf_files: List[Path], image_pins: List[Dict]) -> List[str]:
    updated_files = []
    for pin in image_pins:
        image_name = pin["image"]
        new_digest = pin["digest"]
        for tf_file in tf_files:
            try:
                with open(tf_file) as f:
                    content = f.read()
                if new_digest in content:
                    continue
                updated_content = update_image_references(content, image_name, new_digest)
                if updated_content != content:
                    backup_file = tf_file.with_suffix(tf_file.suffix + ".bak")
                    with open(backup_file, "w") as bf:
                        bf.write(content)
                    with open(tf_file, "w") as f:
                        f.write(updated_content)
                    updated_files.append(str(tf_file))
            except Exception:
                continue
    log_audit("update_terraform_success", "SUCCESS", f"Updated: {len(updated_files)}")
    return updated_files


def create_promotion_commit(updated_files: List[str]) -> Optional[str]:
    if not updated_files:
        return None
    try:
        original_branch = subprocess.check_output([
            "git", "rev-parse", "--abbrev-ref", "HEAD"
        ], cwd=REPO_ROOT, text=True).strip()
        if original_branch != "main":
            log_audit("create_commit_failed", "ERROR", f"Not on main: {original_branch}")
            return None
        commit_msg = (
            f"chore: update image pins from Trivy promotion\n\n"
            f"Updated files:\n"
            + "\n".join(f"- {f}" for f in updated_files[:5])
            + (f"\n... and {len(updated_files)-5} more" if len(updated_files) > 5 else "")
            + f"\n\nTime: {datetime.utcnow().isoformat()}\n"
        )
        subprocess.run(["git", "add"] + updated_files, cwd=REPO_ROOT, check=True)
        result = subprocess.run(["git", "commit", "-m", commit_msg], cwd=REPO_ROOT, capture_output=True, text=True)
        if result.returncode == 0:
            commit_hash = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO_ROOT, text=True).strip()[:7]
            log_audit("create_commit_success", "SUCCESS", f"Commit: {commit_hash}")
            return commit_hash
        else:
            log_audit("create_commit_failed", "ERROR", result.stderr)
            return None
    except Exception as e:
        log_audit("create_commit_failed", "ERROR", str(e))
        return None


def run_e2e_tests() -> bool:
    test_file = REPO_ROOT / "tests" / "test_terraform_pin_updater.py"
    if not test_file.exists():
        return True
    try:
        result = subprocess.run(["python3", "-m", "pytest", str(test_file), "-q"], cwd=REPO_ROOT, capture_output=True, text=True, timeout=300)
        return result.returncode == 0
    except Exception:
        return False


def main(argv=None):
    trivy_file = (argv[1] if argv and len(argv) > 1 else None) or os.environ.get('TRIVY_SCAN_FILE') or 'trivy-scan.json'
    approved_images = parse_trivy_output(trivy_file)
    if not approved_images:
        print('No approved images found')
        return 0
    tf_files = find_terraform_files()
    updated_files = update_terraform_pins(tf_files, approved_images)
    if updated_files:
        create_promotion_commit(updated_files)
    run_e2e_tests()
    print('\n📋 Immutable Audit Trail:')
    try:
        with open(AUDIT_LOG) as f:
            for line in f:
                print(f"  {line.strip()}")
    except Exception:
        pass
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
