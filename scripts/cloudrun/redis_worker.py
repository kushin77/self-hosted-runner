#!/usr/bin/env python3
"""
Redis Worker with Prometheus Metrics
Purpose: Process jobs from Redis queue with comprehensive Prometheus metrics exposure
Related Issue: #2389 EPIC-2.3.2: Redis worker metrics (Prometheus)
"""
import os
import json
import time
import redis
import sys
import signal
import logging
import threading
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler

sys.path.insert(0, os.path.dirname(__file__))

try:
    import persistent_jobs as pj
    from run_migrator import run_migrator
    HAS_MIGRATOR = True
except ImportError:
    HAS_MIGRATOR = False
    logging.warning("persistent_jobs or run_migrator not found")

try:
    from prometheus_client import Counter, Histogram, Gauge, start_http_server
    HAS_PROMETHEUS = True
except ImportError:
    HAS_PROMETHEUS = False
    logging.warning("prometheus_client not installed; install with: pip install prometheus-client")

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration from environment
REDIS_URL = os.environ.get('REDIS_URL', 'redis://127.0.0.1:6379/0')
REDIS_HOST = os.environ.get('REDIS_HOST', 'localhost')
REDIS_PORT = int(os.environ.get('REDIS_PORT', '6379'))
METRICS_PORT = int(os.environ.get('REDIS_METRICS_PORT', '9900'))
METRICS_ADDR = os.environ.get('REDIS_METRICS_ADDR', '0.0.0.0')
HEALTH_CHECK_PORT = int(os.environ.get('REDIS_HEALTH_CHECK_PORT', '9901'))

# Prometheus Metrics (conditional on availability)
if HAS_PROMETHEUS:
    jobs_processed_total = Counter(
        'redis_worker_jobs_processed_total',
        'Total number of jobs processed',
        ['result']  # result: success, failed, error
    )
    
    jobs_processing_duration_seconds = Histogram(
        'redis_worker_job_duration_seconds',
        'Time spent processing jobs',
        buckets=(0.1, 0.5, 1.0, 2.5, 5.0, 10.0, 30.0, 60.0)
    )
    
    jobs_queue_depth = Gauge(
        'redis_worker_queue_depth',
        'Number of jobs in the queue'
    )
    
    jobs_in_progress = Gauge(
        'redis_worker_jobs_in_progress',
        'Number of jobs currently being processed'
    )
    
    worker_uptime_seconds = Gauge(
        'redis_worker_uptime_seconds',
        'Worker uptime in seconds'
    )
    
    redis_connection_errors_total = Counter(
        'redis_worker_connection_errors_total',
        'Total number of Redis connection errors'
    )
    
    worker_health = Gauge(
        'redis_worker_health',
        'Worker health status (1=healthy, 0=unhealthy)'
    )


# ============================================================================
# Health Check Server
# ============================================================================

class HealthCheckServer:
    """Simple health check HTTP server for K8s/systemd probes"""
    
    def __init__(self, port: int = 9901):
        self.port = port
        self.is_healthy = True
        self.ready = True
    
    def start(self):
        """Start health check server in background"""
        try:
            handler = self._create_handler()
            server = HTTPServer(("0.0.0.0", self.port), handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            logger.info(f"Health check server started on port {self.port}")
        except Exception as e:
            logger.error(f"Failed to start health check server: {e}")
    
    def _create_handler(self):
        """Create HTTP request handler"""
        server_instance = self
        
        class HealthHandler(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path == '/health':
                    if server_instance.is_healthy:
                        self.send_response(200)
                        self.send_header('Content-Type', 'application/json')
                        self.end_headers()
                        self.wfile.write(b'{"status":"healthy"}')
                    else:
                        self.send_response(503)
                        self.send_header('Content-Type', 'application/json')
                        self.end_headers()
                        self.wfile.write(b'{"status":"unhealthy"}')
                elif self.path == '/ready':
                    if server_instance.ready:
                        self.send_response(200)
                        self.send_header('Content-Type', 'application/json')
                        self.end_headers()
                        self.wfile.write(b'{"ready":true}')
                    else:
                        self.send_response(503)
                        self.send_header('Content-Type', 'application/json')
                        self.end_headers()
                        self.wfile.write(b'{"ready":false}')
                else:
                    self.send_response(404)
                    self.end_headers()
            
            def log_message(self, format, *args):
                pass  # Suppress health check logs
        
        return HealthHandler


# ============================================================================
# Redis Worker
# ============================================================================

class RedisWorker:
    """Redis-based job processor with Prometheus metrics"""
    
    def __init__(self, redis_url: str):
        self.redis_url = redis_url
        self.running = False
        self.start_time = time.time()
        self.jobs_processed = 0
        self.jobs_failed = 0
        self.is_healthy = False
        self.redis_client = None
        self.health_server = HealthCheckServer(port=HEALTH_CHECK_PORT)
        
        self._connect()
    
    def _connect(self):
        """Establish connection to Redis"""
        try:
            self.redis_client = redis.from_url(self.redis_url, decode_responses=True)
            self.redis_client.ping()
            logger.info(f"Connected to Redis: {self.redis_url}")
            self.is_healthy = True
            if HAS_PROMETHEUS:
                worker_health.set(1)
            self.health_server.is_healthy = True
            self.health_server.ready = True
        except Exception as e:
            logger.error(f"Failed to connect to Redis: {e}")
            if HAS_PROMETHEUS:
                redis_connection_errors_total.inc()
                worker_health.set(0)
            self.is_healthy = False
            self.health_server.is_healthy = False
    
    def _process_job(self, job_id: str, job_data: dict) -> bool:
        """Process a single job"""
        logger.info(f"Processing job {job_id}")
        if HAS_PROMETHEUS:
            jobs_in_progress.inc()
        
        start_time = time.time()
        try:
            # Update status in persistent storage
            if HAS_MIGRATOR:
                pj.set_status(job_id, 'running')
                run_migrator(job_id, job_data)
                pj.set_status(job_id, 'completed')
            else:
                # Fallback: just log the job
                logger.info(f"Processing job data: {json.dumps(job_data, default=str)}")
                time.sleep(0.5)  # Simulate work
            
            # Record metrics
            duration = time.time() - start_time
            if HAS_PROMETHEUS:
                jobs_processing_duration_seconds.observe(duration)
                jobs_processed_total.labels(result='success').inc()
            self.jobs_processed += 1
            
            logger.info(f"✅ Job {job_id} completed in {duration:.2f}s")
            return True
        
        except Exception as e:
            duration = time.time() - start_time
            logger.error(f"❌ Job {job_id} failed: {e}")
            if HAS_PROMETHEUS:
                jobs_processed_total.labels(result='failed').inc()
                jobs_processing_duration_seconds.observe(duration)
            self.jobs_failed += 1
            return False
        
        finally:
            if HAS_PROMETHEUS:
                jobs_in_progress.dec()
    
    def _update_metrics(self):
        """Update metric gauges"""
        try:
            if HAS_PROMETHEUS and self.redis_client:
                queue_depth = self.redis_client.llen('migration_jobs')
                jobs_queue_depth.set(queue_depth)
                
                uptime = time.time() - self.start_time
                worker_uptime_seconds.set(uptime)
        except Exception as e:
            logger.error(f"Error updating metrics: {e}")
    
    def run(self):
        """Main worker loop"""
        logger.info("Redis Worker started")
        self.running = True
        self.health_server.start()
        
        signal.signal(signal.SIGTERM, self._signal_handler)
        signal.signal(signal.SIGINT, self._signal_handler)
        
        while self.running:
            try:
                if not self.redis_client:
                    self._connect()
                    if not self.is_healthy:
                        time.sleep(2)
                        continue
                
                # Pop job from queue (blocking, 5 second timeout)
                result = self.redis_client.blpop('migration_jobs', timeout=5)
                
                if result:
                    queue_name, payload = result
                    try:
                        job = json.loads(payload)
                        job_id = job.get('id')
                        self._process_job(job_id, job)
                    except Exception as e:
                        logger.error(f"Error parsing job: {e}")
                        if HAS_PROMETHEUS:
                            jobs_processed_total.labels(result='error').inc()
                
                # Update metrics regularly
                self._update_metrics()
                
                # Check health
                try:
                    self.redis_client.ping()
                    if not self.is_healthy:
                        logger.info("Redis connection restored")
                        self.is_healthy = True
                        if HAS_PROMETHEUS:
                            worker_health.set(1)
                        self.health_server.is_healthy = True
                except Exception as e:
                    logger.error(f"Redis health check failed: {e}")
                    if HAS_PROMETHEUS:
                        redis_connection_errors_total.inc()
                        worker_health.set(0)
                    self.is_healthy = False
                    self.health_server.is_healthy = False
                    self._connect()
            
            except KeyboardInterrupt:
                break
            except Exception as e:
                logger.error(f"Worker error: {e}")
                time.sleep(2)
        
        logger.info("Redis Worker stopped")
    
    def _signal_handler(self, signum, frame):
        """Handle termination signals"""
        logger.info(f"Received signal {signum}, shutting down...")
        self.running = False


# ============================================================================
# Main
# ============================================================================

def main():
    """Start Redis worker with Prometheus metrics"""
    logger.info("=" * 60)
    logger.info("Redis Worker with Prometheus Metrics")
    logger.info("=" * 60)
    logger.info(f"Redis URL: {REDIS_URL}")
    logger.info(f"Metrics: {'enabled' if HAS_PROMETHEUS else 'disabled'}")
    if HAS_PROMETHEUS:
        logger.info(f"Metrics Port: {METRICS_PORT} ({METRICS_ADDR})")
    logger.info(f"Health Check Port: {HEALTH_CHECK_PORT}")
    
    # Start Prometheus metrics server if available
    if HAS_PROMETHEUS:
        try:
            start_http_server(METRICS_PORT, addr=METRICS_ADDR)
            logger.info(f"Prometheus metrics exposed at http://{METRICS_ADDR}:{METRICS_PORT}/metrics")
        except Exception as e:
            logger.error(f"Failed to start metrics server: {e}")
    
    # Create and run worker
    worker = RedisWorker(redis_url=REDIS_URL)
    
    try:
        worker.run()
    except KeyboardInterrupt:
        logger.info("Shutting down...")
    finally:
        logger.info(f"Worker stats: {worker.jobs_processed} processed, {worker.jobs_failed} failed")


if __name__ == '__main__':
    main()
