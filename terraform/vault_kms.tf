// KMS resources for Vault auto-unseal
// Creates a key ring and a crypto key for Vault auto-unseal and grants
// the specified service account the Encrypter/Decrypter role.

variable "vault_service_account_email" {
  description = "Email of the service account that Vault (or its KMS plugin) will use for auto-unseal"
  type        = string
  default     = ""
}

resource "google_kms_key_ring" "vault" {
  name     = "${local.env_prefix}-vault-keyring"
  location = "us"
}

resource "google_kms_crypto_key" "vault_unseal" {
  name     = "${local.env_prefix}-vault-unseal-key"
  key_ring = google_kms_key_ring.vault.id
  rotation_period = "2592000s" # 30 days

  version_template {
    algorithm = "GOOGLE_SYMMETRIC_ENCRYPTION"
  }
}

resource "google_kms_crypto_key_iam_member" "vault_sa_decrypt" {
  count = var.vault_service_account_email != "" ? 1 : 0

  crypto_key_id = google_kms_crypto_key.vault_unseal.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${var.vault_service_account_email}"
}

output "vault_kms_key_name" {
  value = google_kms_crypto_key.vault_unseal.name
}
