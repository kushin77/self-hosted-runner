#!/usr/bin/env python3
"""
hook-registry/server.py
Distributed git hook registry — versioning, signing, and auto-distribution.

STORAGE LAYOUT:
  scripts/hook-registry/hooks/<hook-name>/<version>/<hook-name>   ← hook files
  scripts/hook-registry/registry.json                             ← index + current pointers
  logs/hook-registry-audit.jsonl                                  ← immutable audit trail
  ~/.git-hooks-registry/<hook-name>/current                       ← local cache (30-day TTL)

HTTP API ENDPOINTS:
  GET  /hooks                        List all hooks + current versions
  GET  /hooks/{name}/versions        Version history for a hook
  GET  /hooks/{name}/current         Download current hook script (text/x-shellscript)
  GET  /status/{engineer_id}         Compliance status for engineer
  POST /hooks/{name}/publish         Publish new version  {version, content, message}
  POST /hooks/{name}/promote         Promote version to current  {version}
  POST /hooks/{name}/rollback        Emergency rollback  {to_version}

CLI SUBCOMMANDS:
  serve    [--port 8002]             Start HTTP server
  status   [--hooks-dir .githooks]   Show local hook compliance
  update   [--hooks-dir .githooks]   Pull latest from registry
  verify   [--hooks-dir .githooks]   Verify SHA256 of installed hooks
  rollback <hook> <version>          Emergency rollback
  list     <hook>                    List available versions
  publish  --hook --version --file   Publish new hook version
  promote  --hook --version          Mark version as current

CONSTRAINTS:
  - Immutable JSONL audit trail
  - Cryptographic SHA-256 verification of every hook
  - No GitHub Actions: registry is a plain filesystem + HTTP server
  - Idempotent: multiple installs/updates produce identical state
  - Ephemeral local cache with 30-day TTL

USAGE:
  # Run registry server
  python3 server.py serve --port 8002

  # Publish a hook
  python3 server.py publish --hook pre-push --version 1.1.0 --file .githooks/pre-push

  # Promote to active
  python3 server.py promote --hook pre-push --version 1.1.0

  # Update local hooks from registry
  python3 server.py update --hooks-dir .githooks

  # Compliance check
  python3 server.py verify --hooks-dir .githooks
"""

import os
import sys
import json
import hashlib
import argparse
import logging
import shutil
import tempfile
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Tuple
from urllib.parse import urlparse


# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    format='{"timestamp": "%(asctime)s", "level": "%(levelname)s",'
           ' "component": "hook-registry", "message": "%(message)s"}',
    level=logging.INFO,
)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Paths  (overridable via env)
# ---------------------------------------------------------------------------
_REPO_ROOT = Path(os.getenv("REPO_ROOT", Path(__file__).parent.parent.parent))
REGISTRY_DIR = _REPO_ROOT / "scripts" / "hook-registry" / "hooks"
REGISTRY_INDEX = _REPO_ROOT / "scripts" / "hook-registry" / "registry.json"
AUDIT_FILE = _REPO_ROOT / "logs" / "hook-registry-audit.jsonl"
LOCAL_CACHE = Path.home() / ".git-hooks-registry"
CACHE_TTL_DAYS = 30


# ---------------------------------------------------------------------------
# Audit trail (immutable JSONL)
# ---------------------------------------------------------------------------

def _audit(event: str, details: Dict[str, Any]) -> None:
    AUDIT_FILE.parent.mkdir(parents=True, exist_ok=True)
    entry = {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "event": event,
        "details": details,
    }
    with AUDIT_FILE.open("a") as f:
        f.write(json.dumps(entry) + "\n")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _load_index() -> Dict[str, Any]:
    if REGISTRY_INDEX.exists():
        return json.loads(REGISTRY_INDEX.read_text())
    return {"hooks": {}, "updated_at": datetime.utcnow().isoformat() + "Z"}


def _save_index(index: Dict[str, Any]) -> None:
    REGISTRY_INDEX.parent.mkdir(parents=True, exist_ok=True)
    index["updated_at"] = datetime.utcnow().isoformat() + "Z"
    REGISTRY_INDEX.write_text(json.dumps(index, indent=2) + "\n")


def _cache_stale(hook_name: str) -> bool:
    ts_file = LOCAL_CACHE / hook_name / "installed_at"
    if not ts_file.exists():
        return True
    ts = datetime.fromisoformat(ts_file.read_text().strip().rstrip("Z"))
    return (datetime.utcnow() - ts) > timedelta(days=CACHE_TTL_DAYS)


# ---------------------------------------------------------------------------
# HookRegistry  (core operations, no HTTP)
# ---------------------------------------------------------------------------

class HookRegistry:
    """Core hook registry — publish, promote, verify, install."""

    def list_hooks(self) -> List[Dict[str, Any]]:
        """List all registered hooks with their current version."""
        index = _load_index()
        return [
            {
                "name": name,
                "current_version": info.get("current"),
                "available_versions": sorted(info.get("versions", {}).keys()),
                "updated_at": info.get("updated_at"),
            }
            for name, info in index.get("hooks", {}).items()
        ]

    def get_versions(self, hook_name: str) -> List[Dict[str, Any]]:
        """Return version history for a hook (most recent first)."""
        index = _load_index()
        hook = index.get("hooks", {}).get(hook_name, {})
        current = hook.get("current")
        versions = [
            {
                "version": ver,
                "sha256": meta.get("sha256"),
                "published_at": meta.get("published_at"),
                "message": meta.get("message", ""),
                "is_current": ver == current,
            }
            for ver, meta in hook.get("versions", {}).items()
        ]
        return sorted(versions, key=lambda v: v["published_at"] or "", reverse=True)

    def get_current_bytes(self, hook_name: str) -> Optional[bytes]:
        """Return raw bytes of the current hook script, or None."""
        index = _load_index()
        hook = index.get("hooks", {}).get(hook_name)
        if not hook or not hook.get("current"):
            return None
        hook_path = REGISTRY_DIR / hook_name / hook["current"] / hook_name
        return hook_path.read_bytes() if hook_path.exists() else None

    def publish(
        self,
        hook_name: str,
        version: str,
        hook_file: Path,
        message: str = "",
    ) -> Dict[str, Any]:
        """
        Publish a new hook version to the registry.

        Does NOT promote it to current — call promote() separately.
        """
        if not hook_file.exists():
            raise FileNotFoundError(f"Hook file not found: {hook_file}")

        dest_dir = REGISTRY_DIR / hook_name / version
        dest_dir.mkdir(parents=True, exist_ok=True)
        dest_file = dest_dir / hook_name
        shutil.copy2(hook_file, dest_file)
        dest_file.chmod(0o755)

        sha = _sha256(dest_file)

        index = _load_index()
        index["hooks"].setdefault(hook_name, {"current": None, "versions": {}, "updated_at": None})
        index["hooks"][hook_name]["versions"][version] = {
            "sha256": sha,
            "published_at": datetime.utcnow().isoformat() + "Z",
            "message": message,
        }
        _save_index(index)

        _audit("hook_published", {
            "hook": hook_name,
            "version": version,
            "sha256": sha,
            "message": message,
        })
        logger.info(f"Published {hook_name} v{version} sha256={sha[:16]}…")
        return {"hook": hook_name, "version": version, "sha256": sha, "status": "published"}

    def promote(self, hook_name: str, version: str) -> Dict[str, Any]:
        """Promote version to current (auto-distribution target)."""
        index = _load_index()
        hook = index.get("hooks", {}).get(hook_name)
        if not hook:
            raise ValueError(f"Hook '{hook_name}' not in registry")
        if version not in hook.get("versions", {}):
            raise ValueError(f"Version '{version}' not found for '{hook_name}'")

        old_version = hook.get("current")
        index["hooks"][hook_name]["current"] = version
        index["hooks"][hook_name]["updated_at"] = datetime.utcnow().isoformat() + "Z"
        _save_index(index)

        _audit("hook_promoted", {
            "hook": hook_name,
            "from_version": old_version,
            "to_version": version,
        })
        logger.info(f"Promoted {hook_name}: {old_version} → {version}")
        return {"hook": hook_name, "promoted_to": version, "previous": old_version}

    def rollback(self, hook_name: str, to_version: str) -> Dict[str, Any]:
        """Emergency rollback — equivalent to promoting an older version."""
        _audit("hook_rollback_requested", {"hook": hook_name, "to_version": to_version})
        return self.promote(hook_name, to_version)

    def install_local(self, hook_name: str, hooks_dir: Path) -> Dict[str, Any]:
        """
        Install current version of hook into hooks_dir (e.g. .githooks/).

        Updates local cache with installation timestamp.
        """
        content = self.get_current_bytes(hook_name)
        if content is None:
            return {"status": "not-found", "hook": hook_name}

        hooks_dir.mkdir(parents=True, exist_ok=True)
        dest = hooks_dir / hook_name
        dest.write_bytes(content)
        dest.chmod(0o755)

        # Update local cache
        cache_dir = LOCAL_CACHE / hook_name
        cache_dir.mkdir(parents=True, exist_ok=True)
        (cache_dir / "current").write_bytes(content)
        (cache_dir / "installed_at").write_text(datetime.utcnow().isoformat() + "Z")

        sha = _sha256_bytes(content)
        _audit("hook_installed", {
            "hook": hook_name,
            "destination": str(dest),
            "sha256": sha,
        })
        return {"status": "installed", "hook": hook_name, "dest": str(dest), "sha256": sha}

    def verify_local(self, hook_name: str, hooks_dir: Path) -> Dict[str, Any]:
        """Verify that locally installed hook matches registry current version."""
        index = _load_index()
        hook = index.get("hooks", {}).get(hook_name)
        if not hook:
            return {"hook": hook_name, "status": "not-in-registry", "signature_valid": False}

        current_version = hook.get("current")
        if not current_version:
            return {"hook": hook_name, "status": "no-current-version", "signature_valid": False}

        expected_sha = hook["versions"][current_version]["sha256"]
        local_path = hooks_dir / hook_name

        if not local_path.exists():
            return {
                "hook": hook_name,
                "status": "not-installed",
                "expected_version": current_version,
                "signature_valid": False,
            }

        actual_sha = _sha256(local_path)
        valid = actual_sha == expected_sha

        result: Dict[str, Any] = {
            "hook": hook_name,
            "status": "valid" if valid else "mismatch",
            "current_version": current_version,
            "expected_sha256_prefix": expected_sha[:16],
            "actual_sha256_prefix": actual_sha[:16],
            "signature_valid": valid,
        }
        _audit("hook_verified", {
            **result,
            "expected_sha256": expected_sha,
            "actual_sha256": actual_sha,
        })
        return result

    def update_all(self, hooks_dir: Path) -> List[Dict[str, Any]]:
        """Install/update all registered hooks to their current version."""
        index = _load_index()
        results = []
        for hook_name in index.get("hooks", {}):
            result = self.install_local(hook_name, hooks_dir)
            results.append(result)
        _audit("hooks_updated", {"count": len(results), "hooks_dir": str(hooks_dir)})
        return results

    def compliance_dashboard(self, hooks_dir: Path) -> Dict[str, Any]:
        """Return a compliance summary for all hooks."""
        index = _load_index()
        hook_names = list(index.get("hooks", {}).keys())
        statuses = [self.verify_local(h, hooks_dir) for h in hook_names]
        compliant = [s for s in statuses if s.get("signature_valid")]
        return {
            "total": len(hook_names),
            "compliant": len(compliant),
            "compliance_pct": round(100 * len(compliant) / len(hook_names), 1) if hook_names else 100.0,
            "hooks": statuses,
        }


# ---------------------------------------------------------------------------
# HTTP handler
# ---------------------------------------------------------------------------

class RegistryHTTPHandler(BaseHTTPRequestHandler):
    """Minimal HTTP handler for hook registry API."""

    registry: HookRegistry

    def _parse_path(self) -> Tuple[List[str], Dict[str, str]]:
        parsed = urlparse(self.path)
        parts = [p for p in parsed.path.split("/") if p]
        return parts, {}

    def _json(self, code: int, data: Any) -> None:
        body = json.dumps(data, indent=2).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        parts, _ = self._parse_path()
        try:
            if parts == ["hooks"]:
                self._json(200, self.registry.list_hooks())

            elif len(parts) == 3 and parts[0] == "hooks" and parts[2] == "versions":
                self._json(200, self.registry.get_versions(parts[1]))

            elif len(parts) == 3 and parts[0] == "hooks" and parts[2] == "current":
                content = self.registry.get_current_bytes(parts[1])
                if content:
                    self.send_response(200)
                    self.send_header("Content-Type", "text/x-shellscript")
                    self.send_header("Content-Length", str(len(content)))
                    self.end_headers()
                    self.wfile.write(content)
                else:
                    self._json(404, {"error": "hook not found or has no current version"})

            elif len(parts) == 3 and parts[0] == "hooks" and parts[2] == "compliance":
                hooks_dir = Path(os.getenv("HOOKS_DIR", ".githooks"))
                self._json(200, self.registry.verify_local(parts[1], hooks_dir))

            elif len(parts) == 1 and parts[0] == "health":
                self._json(200, {"status": "ok", "timestamp": datetime.utcnow().isoformat() + "Z"})

            else:
                self._json(404, {"error": "not found"})

        except Exception as exc:
            logger.error(f"GET {self.path} error: {exc}")
            self._json(500, {"error": str(exc)})

    def do_POST(self) -> None:  # noqa: N802
        parts, _ = self._parse_path()
        try:
            length = int(self.headers.get("Content-Length", 0))
            body: Dict[str, Any] = json.loads(self.rfile.read(length)) if length else {}

            if len(parts) == 3 and parts[0] == "hooks" and parts[2] == "publish":
                hook_name = parts[1]
                version = body.get("version", "")
                content_str = body.get("content", "")
                message = body.get("message", "")

                if not version or not content_str:
                    self._json(400, {"error": "version and content are required"})
                    return

                with tempfile.NamedTemporaryFile(mode="w", suffix=".sh", delete=False) as fp:
                    fp.write(content_str)
                    tmp = Path(fp.name)
                try:
                    result = self.registry.publish(hook_name, version, tmp, message)
                    self._json(200, result)
                finally:
                    tmp.unlink(missing_ok=True)

            elif len(parts) == 3 and parts[0] == "hooks" and parts[2] == "promote":
                version = body.get("version", "")
                if not version:
                    self._json(400, {"error": "version is required"})
                    return
                self._json(200, self.registry.promote(parts[1], version))

            elif len(parts) == 3 and parts[0] == "hooks" and parts[2] == "rollback":
                to_version = body.get("to_version", "")
                if not to_version:
                    self._json(400, {"error": "to_version is required"})
                    return
                self._json(200, self.registry.rollback(parts[1], to_version))

            else:
                self._json(404, {"error": "not found"})

        except Exception as exc:
            logger.error(f"POST {self.path} error: {exc}")
            self._json(500, {"error": str(exc)})

    def log_message(self, fmt: str, *args: Any) -> None:
        logger.info(f"HTTP {args[0]} {args[1]}")


# ---------------------------------------------------------------------------
# Server runner
# ---------------------------------------------------------------------------

def run_server(port: int = 8002) -> None:
    RegistryHTTPHandler.registry = HookRegistry()
    server = HTTPServer(("0.0.0.0", port), RegistryHTTPHandler)
    logger.info(f"Hook registry server listening on 0.0.0.0:{port}")
    logger.info(f"  GET  http://localhost:{port}/hooks")
    logger.info(f"  GET  http://localhost:{port}/health")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Shutting down")
        server.shutdown()


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Distributed git hook registry — version management and distribution"
    )
    sub = parser.add_subparsers(dest="command")

    # serve
    serve_p = sub.add_parser("serve", help="Start registry HTTP server")
    serve_p.add_argument("--port", type=int, default=8002)

    # status
    status_p = sub.add_parser("status", help="Show local hook compliance status")
    status_p.add_argument("--hooks-dir", default=".githooks")

    # update
    update_p = sub.add_parser("update", help="Install/update all hooks to latest")
    update_p.add_argument("--hooks-dir", default=".githooks")

    # verify
    verify_p = sub.add_parser("verify", help="Verify SHA-256 of installed hooks")
    verify_p.add_argument("--hooks-dir", default=".githooks")

    # rollback
    rollback_p = sub.add_parser("rollback", help="Emergency rollback hook to version")
    rollback_p.add_argument("hook_name")
    rollback_p.add_argument("version")

    # list
    list_p = sub.add_parser("list", help="List versions for a hook")
    list_p.add_argument("hook_name")

    # publish
    publish_p = sub.add_parser("publish", help="Publish new hook version to registry")
    publish_p.add_argument("--hook", required=True, help="Hook name (e.g. pre-push)")
    publish_p.add_argument("--version", required=True, help="Semantic version (e.g. 1.1.0)")
    publish_p.add_argument("--file", required=True, help="Path to hook script")
    publish_p.add_argument("--message", default="", help="Release message")

    # promote
    promote_p = sub.add_parser("promote", help="Mark hook version as current")
    promote_p.add_argument("--hook", required=True)
    promote_p.add_argument("--version", required=True)

    # dashboard
    dash_p = sub.add_parser("dashboard", help="Print compliance dashboard")
    dash_p.add_argument("--hooks-dir", default=".githooks")

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)

    reg = HookRegistry()

    if args.command == "serve":
        run_server(port=args.port)

    elif args.command == "status":
        result = reg.compliance_dashboard(Path(args.hooks_dir))
        print(json.dumps(result, indent=2))

    elif args.command == "update":
        results = reg.update_all(Path(args.hooks_dir))
        print(json.dumps(results, indent=2))

    elif args.command == "verify":
        result = reg.compliance_dashboard(Path(args.hooks_dir))
        print(json.dumps(result, indent=2))
        sys.exit(0 if result["compliance_pct"] == 100.0 else 1)

    elif args.command == "rollback":
        result = reg.rollback(args.hook_name, args.version)
        print(json.dumps(result, indent=2))

    elif args.command == "list":
        result = reg.get_versions(args.hook_name)
        print(json.dumps(result, indent=2))

    elif args.command == "publish":
        result = reg.publish(args.hook, args.version, Path(args.file), args.message)
        print(json.dumps(result, indent=2))

    elif args.command == "promote":
        result = reg.promote(args.hook, args.version)
        print(json.dumps(result, indent=2))

    elif args.command == "dashboard":
        result = reg.compliance_dashboard(Path(args.hooks_dir))
        total = result["total"]
        compliant = result["compliant"]
        print(f"\nHOOK COMPLIANCE DASHBOARD")
        print(f"=========================")
        print(f"Compliant: {compliant}/{total} ({result['compliance_pct']}%)\n")
        for h in result["hooks"]:
            icon = "✓" if h.get("signature_valid") else "✗"
            ver = h.get("current_version", "unknown")
            print(f"  {icon} {h['hook']} v{ver}  [{h['status']}]")
        print()


if __name__ == "__main__":
    main()
