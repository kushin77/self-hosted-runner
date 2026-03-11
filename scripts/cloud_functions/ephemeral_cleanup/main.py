#!/usr/bin/env python3
"""
Ephemeral Resource Cleanup - Idempotent, Hands-Off
Automatically cleans up temporary resources created during deployments.
Safe to run repeatedly - all operations are idempotent.
"""

import os
import json
import logging
import base64
from datetime import datetime, timedelta
from typing import Dict, List, Any

from google.cloud import compute_v1, container_v1, run_v1
from google.cloud import logging as cloud_logging

# Logger setup
client_logger = cloud_logging.Client()
client_logger.setup_logging()
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# Environment variables
ENVIRONMENT = os.environ.get("ENVIRONMENT", "staging")
GCP_PROJECT = os.environ.get("GCP_PROJECT")
GCP_REGION = os.environ.get("GCP_REGION", "us-central1")
CLEANUP_LABEL_KEY = "ephemeral"
CLEANUP_LABEL_VALUE = "true"
MAX_AGE_HOURS = 24  # Delete resources older than 24 hours
DRY_RUN = os.environ.get("DRY_RUN", "false").lower() == "true"


class EphemeralResourceCleaner:
    """Idempotent cleaner for ephemeral resources."""

    def __init__(self):
        """Initialize GCP clients."""
        self.compute_client = compute_v1.InstancesClient()
        self.container_client = container_v1.ClusterManagerClient()
        self.run_client = run_v1.ServicesClient()
        self.cleanup_count = 0
        self.skip_count = 0

    def cleanup_compute_instances(self) -> int:
        """Clean up ephemeral Compute Engine instances."""
        logger.info("Scanning for ephemeral Compute instances...")
        cleaned = 0

        try:
            zones = self.compute_client.list_zones(project=GCP_PROJECT)
            for zone in zones:
                zone_name = zone.name
                instances = self.compute_client.list(
                    project=GCP_PROJECT, zone=zone_name
                )

                for instance in instances:
                    if self._is_ephemeral_resource(instance.labels or {}):
                        if self._is_old_enough(instance.creation_timestamp):
                            cleaned += self._delete_compute_instance(
                                GCP_PROJECT, zone_name, instance.name
                            )
                        else:
                            self.skip_count += 1
                            logger.info(
                                f"Skipping recent ephemeral instance: {instance.name}"
                            )

        except Exception as e:
            logger.error(f"Error cleaning Compute instances: {e}")

        return cleaned

    def cleanup_gke_clusters(self) -> int:
        """Clean up ephemeral GKE clusters."""
        logger.info("Scanning for ephemeral GKE clusters...")
        cleaned = 0

        try:
            clusters = self.container_client.list_clusters(
                project_id=GCP_PROJECT, zone=GCP_REGION
            )

            for cluster in clusters.clusters:
                if self._is_ephemeral_resource(cluster.resource_labels or {}):
                    if self._is_old_enough(cluster.create_time):
                        cleaned += self._delete_gke_cluster(cluster.name)
                    else:
                        self.skip_count += 1
                        logger.info(f"Skipping recent GKE cluster: {cluster.name}")

        except Exception as e:
            logger.error(f"Error cleaning GKE clusters: {e}")

        return cleaned

    def cleanup_cloud_run_services(self) -> int:
        """Clean up ephemeral Cloud Run services."""
        logger.info("Scanning for ephemeral Cloud Run services...")
        cleaned = 0

        try:
            parent = f"projects/{GCP_PROJECT}/locations/{GCP_REGION}"
            services = self.run_client.list_services(request={"parent": parent})

            for service in services:
                labels = service.spec.template.metadata.labels or {}
                if self._is_ephemeral_resource(labels):
                    if self._is_old_enough(service.metadata.create_time):
                        cleaned += self._delete_cloud_run_service(service.metadata.name)
                    else:
                        self.skip_count += 1
                        logger.info(
                            f"Skipping recent Cloud Run service: {service.metadata.name}"
                        )

        except Exception as e:
            logger.error(f"Error cleaning Cloud Run services: {e}")

        return cleaned

    def cleanup_storage_objects(self) -> int:
        """Clean up ephemeral temporary files from GCS."""
        from google.cloud import storage

        logger.info("Scanning for ephemeral GCS objects...")
        cleaned = 0
        storage_client = storage.Client(project=GCP_PROJECT)

        try:
            # Look for buckets matching ephemeral pattern
            for bucket in storage_client.list_buckets():
                if "ephemeral" in bucket.name or "temp" in bucket.name:
                    for blob in bucket.list_blobs():
                        if self._is_old_enough(blob.time_created):
                            if self._delete_gcs_object(bucket.name, blob.name):
                                cleaned += 1
                            else:
                                self.skip_count += 1

        except Exception as e:
            logger.error(f"Error cleaning GCS objects: {e}")

        return cleaned

    def _is_ephemeral_resource(self, labels: Dict[str, str]) -> bool:
        """Check if resource is marked as ephemeral."""
        return labels.get(CLEANUP_LABEL_KEY) == CLEANUP_LABEL_VALUE

    def _is_old_enough(self, create_time: Any) -> bool:
        """Check if resource is old enough to delete."""
        if isinstance(create_time, str):
            from datetime import datetime
            create_time = datetime.fromisoformat(create_time.replace("Z", "+00:00"))

        age = datetime.utcnow() - create_time.replace(tzinfo=None)
        return age > timedelta(hours=MAX_AGE_HOURS)

    def _delete_compute_instance(
        self, project: str, zone: str, instance_name: str
    ) -> int:
        """Delete a Compute instance (idempotent)."""
        if DRY_RUN:
            logger.info(f"[DRY_RUN] Would delete Compute instance: {instance_name}")
            return 0

        try:
            operation = self.compute_client.delete(
                project=project, zone=zone, resource=instance_name
            )
            logger.info(f"Scheduled deletion of Compute instance: {instance_name}")
            return 1
        except Exception as e:
            logger.warning(f"Could not delete Compute instance {instance_name}: {e}")
            return 0

    def _delete_gke_cluster(self, cluster_name: str) -> int:
        """Delete a GKE cluster (idempotent)."""
        if DRY_RUN:
            logger.info(f"[DRY_RUN] Would delete GKE cluster: {cluster_name}")
            return 0

        try:
            operation = self.container_client.delete_cluster(
                project_id=GCP_PROJECT, zone=GCP_REGION, cluster_id=cluster_name
            )
            logger.info(f"Scheduled deletion of GKE cluster: {cluster_name}")
            return 1
        except Exception as e:
            logger.warning(f"Could not delete GKE cluster {cluster_name}: {e}")
            return 0

    def _delete_cloud_run_service(self, service_name: str) -> int:
        """Delete a Cloud Run service (idempotent)."""
        if DRY_RUN:
            logger.info(f"[DRY_RUN] Would delete Cloud Run service: {service_name}")
            return 0

        try:
            self.run_client.delete_service(request={"name": service_name})
            logger.info(f"Deleted Cloud Run service: {service_name}")
            return 1
        except Exception as e:
            logger.warning(f"Could not delete Cloud Run service {service_name}: {e}")
            return 0

    def _delete_gcs_object(self, bucket_name: str, object_name: str) -> bool:
        """Delete a GCS object (idempotent)."""
        from google.cloud import storage

        if DRY_RUN:
            logger.info(f"[DRY_RUN] Would delete GCS object: {bucket_name}/{object_name}")
            return False

        try:
            storage_client = storage.Client(project=GCP_PROJECT)
            bucket = storage_client.bucket(bucket_name)
            blob = bucket.blob(object_name)
            blob.delete()
            logger.info(f"Deleted GCS object: {bucket_name}/{object_name}")
            return True
        except Exception as e:
            logger.warning(
                f"Could not delete GCS object {bucket_name}/{object_name}: {e}"
            )
            return False

    def run(self) -> Dict[str, Any]:
        """Run all cleanup operations."""
        logger.info(
            f"Starting ephemeral resource cleanup for {ENVIRONMENT} environment"
        )
        if DRY_RUN:
            logger.warning("Running in DRY_RUN mode - no resources will be deleted")

        start_time = datetime.utcnow()

        # Run all cleanup operations
        compute_cleaned = self.cleanup_compute_instances()
        gke_cleaned = self.cleanup_gke_clusters()
        run_cleaned = self.cleanup_cloud_run_services()
        storage_cleaned = self.cleanup_storage_objects()

        total_cleaned = compute_cleaned + gke_cleaned + run_cleaned + storage_cleaned
        duration = (datetime.utcnow() - start_time).total_seconds()

        result = {
            "environment": ENVIRONMENT,
            "timestamp": start_time.isoformat() + "Z",
            "duration_seconds": duration,
            "total_cleaned": total_cleaned,
            "total_skipped": self.skip_count,
            "compute_instances": compute_cleaned,
            "gke_clusters": gke_cleaned,
            "cloud_run_services": run_cleaned,
            "storage_objects": storage_cleaned,
            "dry_run": DRY_RUN,
        }

        logger.info(f"Cleanup completed: {json.dumps(result)}")
        return result


def cleanup_ephemeral_resources(event, context):
    """Cloud Function entry point."""
    logger.info(f"Received event: {event}")

    try:
        cleaner = EphemeralResourceCleaner()
        result = cleaner.run()
        return {"status": "success", "result": result}
    except Exception as e:
        logger.error(f"Cleanup failed: {e}")
        return {"status": "error", "error": str(e)}
