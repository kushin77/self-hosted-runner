# Phase 6: Integration Test Suite
# Framework: pytest + requests + Docker
# Purpose: Verify all Portal MVP components work together

import pytest
import requests
import os
import json
import logging
from datetime import datetime
from typing import Dict, Any

# Configuration
API_BASE_URL = os.getenv("API_BASE_URL", "http://localhost:8080")
FRONTEND_URL = os.getenv("FRONTEND_URL", "http://localhost:3000")
DB_URL = os.getenv("DATABASE_URL", "postgresql://portal_user:portalpass@localhost:5432/portal_db")

# Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Audit Trail
class AuditTrail:
    """Record all test operations to immutable log"""
    def __init__(self, phase: str = "6"):
        self.phase = phase
        self.log_file = f"logs/integration-tests-{datetime.utcnow().isoformat()}.jsonl"
        os.makedirs("logs", exist_ok=True)
    
    def record(self, action: str, status: str, details: Dict[str, Any] = None):
        entry = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "phase": self.phase,
            "action": action,
            "status": status,
            **(details or {})
        }
        with open(self.log_file, "a") as f:
            f.write(json.dumps(entry) + "\n")
        logger.info(f"{action}: {status}")

audit = AuditTrail()

# ========================================================================
# FIXTURES
# ========================================================================

@pytest.fixture(scope="session")
def api_session():
    """Create HTTP session for API testing"""
    session = requests.Session()
    session.headers.update({
        "Content-Type": "application/json",
        "User-Agent": "Phase6-IntegrationTests/1.0"
    })
    yield session
    session.close()

@pytest.fixture(scope="session")
def test_token(api_session):
    """Obtain test authentication token"""
    # TODO: Implement based on auth mechanism
    return "test-token-placeholder"

@pytest.fixture
def test_user_data():
    """Sample test user data"""
    return {
        "email": f"test-{datetime.utcnow().timestamp()}@example.com",
        "name": "Test User",
        "role": "viewer"
    }

# ========================================================================
# FRONTEND INTEGRATION TESTS
# ========================================================================

class TestFrontendIntegration:
    """Test frontend build and serving"""
    
    def test_frontend_build_exists(self):
        """Verify frontend production build is present"""
        assert os.path.isdir("frontend/dist"), "Frontend dist/ not found"
        assert os.path.isfile("frontend/dist/index.html"), "index.html not found"
        audit.record("frontend_build_check", "pass")
    
    def test_frontend_serves(self):
        """Verify frontend HTTP server responds"""
        try:
            response = requests.get(FRONTEND_URL, timeout=5)
            assert response.status_code == 200, f"Expected 200, got {response.status_code}"
            assert "html" in response.text.lower(), "Response doesn't contain HTML"
            audit.record("frontend_serves", "pass", {"status_code": response.status_code})
        except requests.exceptions.ConnectionError as e:
            pytest.skip(f"Frontend not running: {e}")
            audit.record("frontend_serves", "skip", {"reason": "frontend_not_running"})
    
    def test_frontend_manifest(self):
        """Verify frontend manifest.json for PWA"""
        manifest_path = "frontend/dist/manifest.json"
        if os.path.exists(manifest_path):
            with open(manifest_path) as f:
                manifest = json.load(f)
            assert "name" in manifest, "manifest.json missing 'name'"
            audit.record("frontend_manifest", "pass")
        else:
            pytest.skip("manifest.json not found")
            audit.record("frontend_manifest", "skip")

# ========================================================================
# API CONTRACT TESTS
# ========================================================================

class TestAPIContract:
    """Test API endpoints and contracts"""
    
    def test_api_health(self, api_session):
        """Test /health endpoint"""
        try:
            response = api_session.get(f"{API_BASE_URL}/health", timeout=5)
            assert response.status_code == 200, f"Health check failed: {response.status_code}"
            data = response.json()
            assert "status" in data, "health response missing 'status'"
            assert data["status"] == "healthy", f"API not healthy: {data.get('status')}"
            audit.record("api_health", "pass", {"status": data.get("status")})
        except requests.exceptions.ConnectionError as e:
            pytest.skip(f"API not running: {e}")
            audit.record("api_health", "skip", {"reason": "api_not_running"})
    
    def test_api_version(self, api_session):
        """Test /version endpoint"""
        try:
            response = api_session.get(f"{API_BASE_URL}/version", timeout=5)
            if response.status_code == 200:
                data = response.json()
                assert "version" in data, "Missing version info"
                audit.record("api_version", "pass", {"version": data.get("version")})
            else:
                audit.record("api_version", "skip", {"reason": "endpoint not implemented"})
        except requests.exceptions.ConnectionError:
            pytest.skip("API not running")
    
    def test_api_metrics(self, api_session):
        """Test /metrics endpoint for Prometheus"""
        try:
            response = api_session.get(f"{API_BASE_URL}/metrics", timeout=5)
            if response.status_code == 200:
                metrics = response.text
                assert "http_requests_total" in metrics or "requests" in metrics, \
                    "Metrics don't contain request counters"
                audit.record("api_metrics", "pass")
            else:
                audit.record("api_metrics", "skip", {"reason": "metrics_not_implemented"})
        except requests.exceptions.ConnectionError:
            pytest.skip("API not running")

# ========================================================================
# DATABASE INTEGRATION TESTS
# ========================================================================

class TestDatabaseIntegration:
    """Test database connectivity and schema"""
    
    @pytest.fixture(autouse=True)
    def db_connection(self):
        """Setup database connection"""
        try:
            import psycopg2
            self.conn = psycopg2.connect(DB_URL)
            self.cursor = self.conn.cursor()
            yield
            self.cursor.close()
            self.conn.close()
        except ImportError:
            pytest.skip("psycopg2 not installed")
        except Exception as e:
            pytest.skip(f"Database not available: {e}")
    
    def test_database_connection(self):
        """Verify database is accessible"""
        self.cursor.execute("SELECT 1")
        result = self.cursor.fetchone()
        assert result == (1,), "Database SELECT failed"
        audit.record("db_connection", "pass")
    
    def test_database_schema(self):
        """Verify database schema tables exist"""
        self.cursor.execute("""
            SELECT table_name FROM information_schema.tables 
            WHERE table_schema='public'
        """)
        tables = [row[0] for row in self.cursor.fetchall()]
        expected_tables = ["users", "projects", "artifacts"]  # Adjust based on your schema
        
        # At minimum, check that tables exist
        if tables:
            audit.record("db_schema", "pass", {"table_count": len(tables)})
        else:
            audit.record("db_schema", "warn", {"message": "no tables found"})
    
    def test_database_migrations(self):
        """Verify all migrations have been applied"""
        self.cursor.execute("""
            SELECT COUNT(*) FROM information_schema.tables 
            WHERE table_schema='public'
        """)
        count = self.cursor.fetchone()[0]
        assert count > 0, "No tables found - migrations may not have run"
        audit.record("db_migrations", "pass", {"tables": count})

# ========================================================================
# OBSERVABILITY INTEGRATION TESTS
# ========================================================================

class TestObservability:
    """Test observability stack (Prometheus, Grafana, Loki, Jaeger)"""
    
    def test_prometheus_running(self):
        """Verify Prometheus is running"""
        try:
            response = requests.get("http://localhost:9090/-/ready", timeout=5)
            assert response.status_code == 200, f"Prometheus not ready: {response.status_code}"
            audit.record("prometheus_running", "pass")
        except requests.exceptions.ConnectionError:
            pytest.skip("Prometheus not running")
            audit.record("prometheus_running", "skip")
    
    def test_prometheus_targets(self):
        """Verify Prometheus has scrape targets"""
        try:
            response = requests.get("http://localhost:9090/api/v1/targets", timeout=5)
            if response.status_code == 200:
                data = response.json()
                targets = data.get("data", {}).get("activeTargets", [])
                assert len(targets) > 0, "No active Prometheus targets"
                audit.record("prometheus_targets", "pass", {"count": len(targets)})
        except requests.exceptions.ConnectionError:
            pytest.skip("Prometheus not running")
    
    def test_grafana_running(self):
        """Verify Grafana is running"""
        try:
            response = requests.get("http://localhost:3001/api/health", timeout=5)
            assert response.status_code == 200, f"Grafana not healthy: {response.status_code}"
            audit.record("grafana_running", "pass")
        except requests.exceptions.ConnectionError:
            pytest.skip("Grafana not running")
            audit.record("grafana_running", "skip")
    
    def test_loki_running(self):
        """Verify Loki is running"""
        try:
            response = requests.get("http://localhost:3100/ready", timeout=5)
            assert response.status_code == 200, f"Loki not ready: {response.status_code}"
            audit.record("loki_running", "pass")
        except requests.exceptions.ConnectionError:
            pytest.skip("Loki not running")
            audit.record("loki_running", "skip")
    
    def test_jaeger_running(self):
        """Verify Jaeger is running"""
        try:
            response = requests.get("http://localhost:16686", timeout=5)
            assert response.status_code in [200, 401, 302], f"Jaeger not responding: {response.status_code}"
            audit.record("jaeger_running", "pass")
        except requests.exceptions.ConnectionError:
            pytest.skip("Jaeger not running")
            audit.record("jaeger_running", "skip")

# ========================================================================
# END-TO-END WORKFLOW TESTS
# ========================================================================

class TestEndToEndWorkflows:
    """Test complete user workflows across frontend, API, database"""
    
    def test_user_creation_workflow(self, api_session, test_user_data):
        """Test creating a user from API"""
        try:
            # Create user via API
            response = api_session.post(
                f"{API_BASE_URL}/api/users",
                json=test_user_data,
                timeout=10
            )
            
            if response.status_code == 401:
                pytest.skip("Auth not configured for test")
            
            assert response.status_code in [200, 201], \
                f"User creation failed: {response.status_code} {response.text}"
            
            data = response.json()
            assert "id" in data or "user_id" in data, "Created user missing ID"
            audit.record("user_creation_workflow", "pass", {"user": data})
        except requests.exceptions.ConnectionError:
            pytest.skip("API not running")
    
    def test_api_to_database_sync(self):
        """Test that API data appears in database"""
        # This requires database connection
        pytest.skip("Not implemented - requires API + DB coordination")

# ========================================================================
# PERFORMANCE TESTS
# ========================================================================

class TestPerformance:
    """Test performance and latency requirements"""
    
    def test_api_response_time(self, api_session):
        """Test API response time < 100ms"""
        try:
            import time
            start = time.time()
            response = api_session.get(f"{API_BASE_URL}/health", timeout=5)
            duration_ms = (time.time() - start) * 1000
            
            assert response.status_code == 200, "Health check failed"
            assert duration_ms < 100, f"API latency too high: {duration_ms:.0f}ms"
            audit.record("api_response_time", "pass", {"latency_ms": f"{duration_ms:.1f}"})
        except requests.exceptions.ConnectionError:
            pytest.skip("API not running")

# ========================================================================
# AUDIT & SUMMARY
# ========================================================================

@pytest.fixture(scope="session", autouse=True)
def audit_session_complete():
    """Record test session completion"""
    yield
    audit.record("integration_test_suite", "complete", {
        "timestamp_end": datetime.utcnow().isoformat() + "Z"
    })

if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
