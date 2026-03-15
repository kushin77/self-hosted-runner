"""
credential_manager.py — Python-importable alias for credential-manager.py

credential-manager.py uses a hyphen (not importable directly).
This module re-exports CredentialManager using importlib so all imports work:
  from auth.credential_manager import CredentialManager
"""
import importlib.util
import sys
from pathlib import Path

_src = Path(__file__).parent / "credential-manager.py"
_spec = importlib.util.spec_from_file_location("auth._credential_manager_impl", _src)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)

CredentialManager = _mod.CredentialManager

__all__ = ["CredentialManager"]
