import importlib
import logging
from typing import Callable, List, Optional, Dict, Any

from ..orchestrator import RemediationStep

logger = logging.getLogger(__name__)


def _find_callable(module, candidates: List[str]) -> Optional[Callable[..., bool]]:
    for name in candidates:
        if hasattr(module, name):
            attr = getattr(module, name)
            if callable(attr):
                return attr
    return None


def create_step_from_module(module_path: str,
                            func_candidates: List[str],
                            step_name: str,
                            max_retries: int = 3,
                            retry_delay: float = 1.0,
                            call_kwargs: Optional[Dict[str, Any]] = None) -> RemediationStep:
    """Create a RemediationStep by importing a module and locating a callable.

    The adapter tries the list of candidate function names in order and wraps the
    first callable it finds. The callable will be invoked with `call_kwargs` if provided.
    If the module or callable isn't available, the returned step will fail fast and log.
    """
    call_kwargs = call_kwargs or {}

    try:
        module = importlib.import_module(module_path)
    except Exception as e:
        def _missing_action():
            logger.error("Adapter import failed for %s: %s", module_path, e)
            return False

        return RemediationStep(step_name, _missing_action, max_retries=max_retries, retry_delay=retry_delay)

    func = _find_callable(module, func_candidates)

    if func is None:
        def _no_func_action():
            logger.error("No candidate callable found in %s (candidates=%s)", module_path, func_candidates)
            return False

        return RemediationStep(step_name, _no_func_action, max_retries=max_retries, retry_delay=retry_delay)

    def _action():
        try:
            # Call with kwargs when supported; most remediation functions are zero-arg
            return bool(func(**call_kwargs)) if call_kwargs else bool(func())
        except TypeError:
            # Fallback: try calling without kwargs
            try:
                return bool(func())
            except Exception as e:
                logger.exception("Adapter action failed for %s: %s", module_path, e)
                return False
        except Exception as e:
            logger.exception("Adapter action failed for %s: %s", module_path, e)
            return False

    return RemediationStep(step_name, _action, max_retries=max_retries, retry_delay=retry_delay)


def wrap_callable_as_step(callable_obj: Callable[..., bool], step_name: str,
                          max_retries: int = 3, retry_delay: float = 1.0,
                          call_kwargs: Optional[Dict[str, Any]] = None) -> RemediationStep:
    call_kwargs = call_kwargs or {}

    def _action():
        try:
            return bool(callable_obj(**call_kwargs)) if call_kwargs else bool(callable_obj())
        except Exception:
            logger.exception("Wrapped callable failed for step %s", step_name)
            return False

    return RemediationStep(step_name, _action, max_retries=max_retries, retry_delay=retry_delay)
