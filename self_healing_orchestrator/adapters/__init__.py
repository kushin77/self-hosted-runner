from .adapter_base import create_step_from_module, wrap_callable_as_step

# Candidate function names commonly used by remediation modules
_COMMON_FN_CANDIDATES = [
    "execute",
    "run",
    "remediate",
    "apply",
    "trigger",
    "start",
    "handle",
]


def retry_engine_step(step_name: str, max_retries: int = 3, retry_delay: float = 1.0, call_kwargs=None):
    return create_step_from_module("self_healing_retry_engine", _COMMON_FN_CANDIDATES, step_name,
                                   max_retries=max_retries, retry_delay=retry_delay, call_kwargs=call_kwargs)


def auto_merge_step(step_name: str, max_retries: int = 2, retry_delay: float = 1.0, call_kwargs=None):
    return create_step_from_module("self_healing_auto_merge", _COMMON_FN_CANDIDATES, step_name,
                                   max_retries=max_retries, retry_delay=retry_delay, call_kwargs=call_kwargs)


def predictive_healer_step(step_name: str, max_retries: int = 2, retry_delay: float = 0.5, call_kwargs=None):
    return create_step_from_module("self_healing_predictive", _COMMON_FN_CANDIDATES, step_name,
                                   max_retries=max_retries, retry_delay=retry_delay, call_kwargs=call_kwargs)


def state_recovery_step(step_name: str, max_retries: int = 1, retry_delay: float = 0.2, call_kwargs=None):
    return create_step_from_module("self_healing_state", _COMMON_FN_CANDIDATES, step_name,
                                   max_retries=max_retries, retry_delay=retry_delay, call_kwargs=call_kwargs)


def escalation_step(step_name: str, max_retries: int = 1, retry_delay: float = 0.5, call_kwargs=None):
    return create_step_from_module("self_healing_escalation", _COMMON_FN_CANDIDATES, step_name,
                                   max_retries=max_retries, retry_delay=retry_delay, call_kwargs=call_kwargs)


def rollback_step(step_name: str, max_retries: int = 3, retry_delay: float = 1.0, call_kwargs=None):
    return create_step_from_module("self_healing_rollback", _COMMON_FN_CANDIDATES, step_name,
                                   max_retries=max_retries, retry_delay=retry_delay, call_kwargs=call_kwargs)


def pr_prioritizer_step(step_name: str, max_retries: int = 2, retry_delay: float = 0.5, call_kwargs=None):
    return create_step_from_module("self_healing_pr_prioritization", _COMMON_FN_CANDIDATES, step_name,
                                   max_retries=max_retries, retry_delay=retry_delay, call_kwargs=call_kwargs)
