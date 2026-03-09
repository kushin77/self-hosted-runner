#!/usr/bin/env python3
"""
AI-Oracle Integration Layer for Ephemeral Runner Lifecycle

Purpose: Optional integration with AI-Oracle service to provide intelligent
TTL hints based on job history, patterns, and resource utilization predictions.

Features:
- Webhook-based communication with AI-Oracle
- Caching of AI hints for performance
- Fallback to policy-based TTL if AI-Oracle unavailable
- Confidence-based hint filtering
- Audit trail of AI guidance

Architecture:
1. Lifecycle controller requests TTL hint from AI-Oracle
2. AI-Oracle analyzes job type, historical data, patterns
3. AI-Oracle returns TTL recommendation with confidence score
4. Controller uses hint to adjust final TTL (if confidence > threshold)
5. Cache hint to avoid repeated requests for similar jobs
"""

import json
import logging
import time
import requests
from typing import Dict, Optional, Tuple
from datetime import datetime, timedelta
from pathlib import Path
from hashlib import sha256
import threading
from concurrent.futures import ThreadPoolExecutor
import os


class AIOracle:
    """Interface to AI-Oracle service for intelligent TTL guidance"""

    def __init__(self, webhook_url: str = "", timeout_ms: int = 5000,
                 cache_ttl_seconds: int = 300, confidence_threshold: float = 0.75):
        """Initialize AI-Oracle interface
        
        Args:
            webhook_url: AI-Oracle webhook endpoint
            timeout_ms: Request timeout in milliseconds
            cache_ttl_seconds: Cache TTL hints for this duration
            confidence_threshold: Minimum confidence score to use hints (0-1)
        """
        self.webhook_url = webhook_url
        self.timeout = timeout_ms / 1000.0  # Convert to seconds
        self.cache_ttl = cache_ttl_seconds
        self.confidence_threshold = confidence_threshold
        
        self.logger = logging.getLogger("ai-oracle")
        
        # In-memory cache for hints
        self.cache: Dict[str, Dict] = {}
        self.cache_lock = threading.Lock()
        
        # Thread pool for async requests
        self.executor = ThreadPoolExecutor(max_workers=2)
        
        self.logger.info(f"AI-Oracle initialized (webhook={webhook_url}, "
                        f"timeout={timeout_ms}ms, cache_ttl={cache_ttl_seconds}s)")

    def _cache_key(self, job_type: str, labels: list) -> str:
        """Generate cache key for a job configuration"""
        key_str = f"{job_type}:{','.join(sorted(labels))}"
        return sha256(key_str.encode()).hexdigest()[:16]

    def _get_cached_hint(self, job_type: str, labels: list) -> Optional[Dict]:
        """Get cached TTL hint if available and not expired"""
        cache_key = self._cache_key(job_type, labels)
        
        with self.cache_lock:
            if cache_key in self.cache:
                entry = self.cache[cache_key]
                age = time.time() - entry.get("cached_at", 0)
                
                if age < self.cache_ttl:
                    self.logger.debug(f"Cache hit for {job_type} (age={age:.0f}s)")
                    return entry.get("hint")
                else:
                    # Expired, remove from cache
                    del self.cache[cache_key]
        
        return None

    def _cache_hint(self, job_type: str, labels: list, hint: Dict) -> None:
        """Cache a TTL hint"""
        cache_key = self._cache_key(job_type, labels)
        
        with self.cache_lock:
            self.cache[cache_key] = {
                "hint": hint,
                "cached_at": time.time(),
                "job_type": job_type,
                "labels": labels
            }

    def get_ttl_hint(self, job_type: str, labels: list = None,
                     job_duration_hint: int = None,
                     workflow_context: Dict = None) -> Optional[Dict]:
        """Request TTL hint from AI-Oracle
        
        Args:
            job_type: Type of job (build, test, deploy, etc.)
            labels: Additional labels for job classification
            job_duration_hint: Expected job duration in seconds
            workflow_context: Additional context (repo, branch, etc.)
        
        Returns:
            Dict with TTL hint or None if unavailable
            Example: {
                "ttl_seconds": 3600,
                "confidence": 0.92,
                "reasoning": "Similar builds average 45 minutes",
                "adjustments": {
                    "base_ttl": 1800,
                    "multiplier": 1.5
                }
            }
        """
        labels = labels or []
        
        # Check cache first
        cached = self._get_cached_hint(job_type, labels)
        if cached:
            return cached
        
        # If no webhook configured, can't query
        if not self.webhook_url:
            self.logger.debug("AI-Oracle disabled (no webhook configured)")
            return None
        
        try:
            hint = self._request_hint(job_type, labels, job_duration_hint, workflow_context)
            
            if hint and hint.get("confidence", 0) >= self.confidence_threshold:
                self._cache_hint(job_type, labels, hint)
                return hint
            elif hint:
                self.logger.debug(f"Hint confidence {hint.get('confidence')} below threshold "
                                f"{self.confidence_threshold}")
            
            return None
        except Exception as e:
            self.logger.error(f"Failed to get AI-Oracle hint: {e}")
            return None

    def _request_hint(self, job_type: str, labels: list, job_duration: Optional[int],
                     context: Optional[Dict]) -> Optional[Dict]:
        """Make HTTP request to AI-Oracle webhook"""
        
        payload = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "request_id": f"{job_type}-{int(time.time())}",
            "job_type": job_type,
            "labels": labels,
            "job_duration_hint": job_duration,
            "context": context or {},
            "requested_fields": ["ttl_seconds", "confidence", "reasoning"]
        }
        
        try:
            self.logger.debug(f"Requesting hint from AI-Oracle for {job_type}")
            
            response = requests.post(
                self.webhook_url,
                json=payload,
                timeout=self.timeout,
                headers={
                    "Content-Type": "application/json",
                    "User-Agent": "EphemeralLifecycleController/1.0"
                }
            )
            
            if response.status_code == 200:
                hint = response.json()
                self.logger.info(f"Got AI hint for {job_type}: TTL={hint.get('ttl_seconds')}s, "
                               f"confidence={hint.get('confidence'):.2f}")
                return hint
            else:
                self.logger.warning(f"AI-Oracle returned {response.status_code}")
                return None
                
        except requests.Timeout:
            self.logger.warning(f"AI-Oracle request timed out ({self.timeout}s)")
            return None
        except Exception as e:
            self.logger.error(f"AI-Oracle request failed: {e}")
            return None

    def apply_hint(self, base_ttl: int, max_ttl: int, 
                   hint: Dict, adjustment_factor: float = 0.5) -> int:
        """Apply AI-Oracle hint to adjust TTL
        
        Args:
            base_ttl: Base TTL from policy
            max_ttl: Maximum allowed TTL
            hint: TTL hint from AI-Oracle
            adjustment_factor: How much to adjust (0-1); 0=ignore, 1=fully apply
        
        Returns:
            Adjusted TTL in seconds
        """
        if not hint:
            return base_ttl
        
        ai_ttl = hint.get("ttl_seconds", base_ttl)
        confidence = hint.get("confidence", 0)
        
        # Adjust based on confidence and adjustment factor
        # Formula: adjusted_ttl = base_ttl + (ai_ttl - base_ttl) * adjustment_factor * confidence
        adjustment = (ai_ttl - base_ttl) * adjustment_factor * confidence
        adjusted_ttl = int(base_ttl + adjustment)
        
        # Enforce max TTL
        final_ttl = min(adjusted_ttl, max_ttl)
        
        self.logger.info(f"Applied AI hint: {base_ttl}s → {final_ttl}s "
                        f"(adjustment={adjustment:.0f}s, factor={adjustment_factor}, "
                        f"confidence={confidence:.2f})")
        
        return final_ttl

    def log_hint_usage(self, job_type: str, hint: Dict, actual_duration: int) -> None:
        """Log hint usage and actual job duration for model improvement
        
        This data helps the AI-Oracle model learn and improve over time.
        """
        if not self.webhook_url:
            return
        
        feedback = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "job_type": job_type,
            "hint_ttl": hint.get("ttl_seconds"),
            "hint_confidence": hint.get("confidence"),
            "actual_duration": actual_duration,
            "accuracy": "high" if abs(actual_duration - hint.get("ttl_seconds", 0)) < 300
                       else "medium" if abs(actual_duration - hint.get("ttl_seconds", 0)) < 900
                       else "low",
            "request_id": hint.get("request_id")
        }
        
        try:
            # Send feedback asynchronously
            self.executor.submit(
                requests.post,
                f"{self.webhook_url}/feedback",
                json=feedback,
                timeout=self.timeout
            )
            self.logger.debug(f"Logged hint feedback for {job_type}")
        except Exception as e:
            self.logger.error(f"Failed to log feedback: {e}")

    def get_cache_stats(self) -> Dict:
        """Get cache statistics"""
        with self.cache_lock:
            total_entries = len(self.cache)
            expired = sum(1 for e in self.cache.values() 
                         if time.time() - e.get("cached_at", 0) >= self.cache_ttl)
        
        return {
            "total_cached_hints": total_entries,
            "expired_entries": expired,
            "active_entries": total_entries - expired,
            "cache_ttl_seconds": self.cache_ttl
        }

    def clear_cache(self) -> None:
        """Clear all cached hints"""
        with self.cache_lock:
            self.cache.clear()
        self.logger.info("Cache cleared")


class AIOracleIntegration:
    """Integration helper for using AI-Oracle in lifecycle controller"""

    def __init__(self, config: Dict):
        """Initialize AI-Oracle integration from config
        
        Args:
            config: Configuration dict with ai_oracle settings from ttl-policies.yaml
        """
        ai_config = config.get("ai_oracle", {})
        
        self.enabled = ai_config.get("enabled", False)
        self.adjustment_factor = ai_config.get("adjustment_factor", 0.5)
        
        if self.enabled:
            self.oracle = AIOracle(
                webhook_url=ai_config.get("webhook_url", ""),
                timeout_ms=ai_config.get("timeout_ms", 5000),
                cache_ttl_seconds=ai_config.get("cache_ttl_seconds", 300),
                confidence_threshold=ai_config.get("confidence_threshold", 0.75)
            )
        else:
            self.oracle = None

    def get_adjusted_ttl(self, base_ttl: int, max_ttl: int, job_type: str,
                        labels: list = None, job_duration: int = None) -> Tuple[int, str]:
        """Get TTL adjusted by AI-Oracle hints
        
        Returns:
            (adjusted_ttl, source) where source is "ai-oracle" or "policy"
        """
        if not self.enabled or not self.oracle:
            return base_ttl, "policy"
        
        try:
            hint = self.oracle.get_ttl_hint(job_type, labels, job_duration)
            
            if hint:
                adjusted_ttl = self.oracle.apply_hint(
                    base_ttl, max_ttl, hint,
                    adjustment_factor=self.adjustment_factor
                )
                return adjusted_ttl, "ai-oracle"
        except Exception as e:
            logging.getLogger("ai-oracle").error(f"AI-Oracle integration failed: {e}")
        
        return base_ttl, "policy"


# Example of standalone AI-Oracle mock service for testing
class MockAIOracle:
    """Mock AI-Oracle implementation for testing and development"""

    @staticmethod
    def generate_mock_hint(job_type: str, labels: list = None) -> Dict:
        """Generate a mock TTL hint based on job characteristics"""
        
        # Simplified heuristics for demonstration
        base_hints = {
            "test": {"ttl": 900, "confidence": 0.85},
            "build": {"ttl": 3600, "confidence": 0.88},
            "integration": {"ttl": 7200, "confidence": 0.80},
            "deploy": {"ttl": 14400, "confidence": 0.82},
            "infrastructure": {"ttl": 28800, "confidence": 0.75}
        }
        
        hint_info = base_hints.get(job_type, {"ttl": 1800, "confidence": 0.70})
        
        # Adjust based on labels
        if "production" in (labels or []):
            hint_info["ttl"] = int(hint_info["ttl"] * 1.2)
            hint_info["confidence"] = min(hint_info["confidence"] + 0.05, 0.99)
        
        if "critical" in (labels or []):
            hint_info["ttl"] = int(hint_info["ttl"] * 1.5)
            hint_info["confidence"] = min(hint_info["confidence"] + 0.10, 0.99)
        
        return {
            "ttl_seconds": hint_info["ttl"],
            "confidence": hint_info["confidence"],
            "reasoning": f"Mock hint for {job_type} with labels {labels}",
            "source": "mock-oracle"
        }


if __name__ == "__main__":
    # Simple test
    logging.basicConfig(level=logging.DEBUG)
    
    # Test with mock oracle
    hint = MockAIOracle.generate_mock_hint("build", ["production", "critical"])
    print(f"Mock hint: {hint}")
    
    # Test AI-Oracle integration
    config = {
        "ai_oracle": {
            "enabled": False,  # Set to True if AI-Oracle is available
            "webhook_url": "http://localhost:8000/oracle",
            "adjustment_factor": 0.5
        }
    }
    
    integration = AIOracleIntegration(config)
    adjusted_ttl, source = integration.get_adjusted_ttl(
        base_ttl=1800,
        max_ttl=3600,
        job_type="build",
        labels=["production"]
    )
    
    print(f"Adjusted TTL: {adjusted_ttl}s (from {source})")
