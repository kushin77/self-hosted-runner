output "image_pin_service_url" {
  value = google_cloud_run_service.image_pin.status[0].url
}
