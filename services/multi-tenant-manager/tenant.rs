// Multi-tenant provisioner configuration system
// Supports multiple GitHub organizations with per-org overrides

export interface TenantConfig {
  org_name: string;
  github_org_id: number;
  vault_policy: string;
  terraform_module_path: string;
  runner_labels: string[];
  runner_group_name?: string;
  cost_center?: string;
  environment: 'production' | 'staging';
  mTLS_enabled: boolean;
}

export interface MultiTenantManager {
  tenants: Map<string, TenantConfig>;
  load_tenant_config(org_name: string): Promise<TenantConfig>;
  validate_tenant_request(org_id: number, request: ProvisioningRequest): Promise<boolean>;
  get_org_vault_policy(org_name: string): Promise<string>;
  get_org_terraform_module(org_name: string): Promise<string>;
  track_provisioning_cost(org_name: string, cost_usd: number): Promise<void>;
}

/// Load tenant configurations from Vault or config file
pub async fn load_tenant_config(org_name: &str) -> Result<TenantConfig, Error> {
  let vault_client = VaultClient::new();
  
  // Try to load from Vault first (production)
  let config = vault_client
    .read(&format!("secret/data/provisioner/orgs/{}", org_name))
    .await
    .ok()
    .and_then(|v| serde_json::from_value(v).ok())
    .unwrap_or_else(|| {
      // Fallback to defaults
      TenantConfig {
        org_name: org_name.to_string(),
        github_org_id: 0,
        vault_policy: format!("provisioner-worker-org-{}", org_name),
        terraform_module_path: "modules/runner".to_string(),
        runner_labels: vec!["self-hosted".to_string()],
        environment: "production".to_string(),
        mTLS_enabled: true,
      }
    });

  Ok(config)
}

/// Validate provisioning request against tenant RBAC
pub async fn validate_tenant_request(
  org_id: u64,
  request: &ProvisioningRequest,
) -> Result<bool, Error> {
  // Step 1: Verify org_id matches request signature
  if request.github_org_id != org_id {
    return Ok(false);
  }

  // Step 2: Check request signature (HMAC-SHA256)
  let signature = request.signature.clone();
  let expected_signature = compute_hmac_sha256(&request.body, &request.org_secret);
  if signature != expected_signature {
    warn!("Request signature mismatch for org {}", org_id);
    return Ok(false);
  }

  // Step 3: Verify tenant has permission to this resource
  let config = load_tenant_config(&request.org_name).await?;
  let vault_client = VaultClient::new();
  
  let has_permission = vault_client
    .verify_policy(&config.vault_policy, "provisioner:create")
    .await?;

  if !has_permission {
    warn!("Tenant {} not authorized for provisioning", request.org_name);
    return Ok(false);
  }

  // Step 4: Log audit trail
  info!("Provisioning request validated for org: {} (id: {})", request.org_name, org_id);

  Ok(true)
}

/// Track provisioning cost per tenant for billing/chargeback
pub async fn track_provisioning_cost(
  org_name: &str,
  cost_usd: f64,
) -> Result<(), Error> {
  let timestamp = chrono::Utc::now();
  
  // Write cost event to audit system
  let event = CostEvent {
    org_name: org_name.to_string(),
    cost_usd,
    timestamp,
    source: "provisioner-worker".to_string(),
  };

  // Store in Redis timeseries (for Prometheus scraping)
  let redis_key = format!("metrics:provisioner:cost:{}", org_name);
  redis_client
    .zadd(&redis_key, timestamp.timestamp(), cost_usd)
    .await?;

  info!("Cost tracked: {} org={} cost=${:.2}", timestamp, org_name, cost_usd);

  Ok(())
}

/// Get per-org Terraform module path
pub async fn get_org_terraform_module(org_name: &str) -> Result<String, Error> {
  let config = load_tenant_config(org_name).await?;
  Ok(config.terraform_module_path)
}

// Example provisioning request with multi-tenant context
#[derive(Debug, Serialize, Deserialize)]
pub struct ProvisioningRequest {
  pub org_name: String,
  pub github_org_id: u64,
  pub runners_count: u32,
  pub runner_labels: Vec<String>,
  pub runner_group_name: Option<String>,
  pub terraform_vars: serde_json::Value,
  pub body: Vec<u8>,                   // For signature verification
  pub signature: String,               // HMAC-SHA256
  pub org_secret: String,              // Org-specific signing key
}

/// Render Terraform variables per-org
pub fn render_terraform_vars(org_name: &str, request: &ProvisioningRequest) -> Result<String, Error> {
  let config = tokio::runtime::Runtime::new()?.block_on(load_tenant_config(org_name))?;
  
  let mut vars = request.terraform_vars.clone();
  vars["org_name"] = json!(config.org_name);
  vars["cost_center"] = json!(config.cost_center.unwrap_or_default());
  vars["environment"] = json!(config.environment);
  vars["runner_labels"] = json!(config.runner_labels);

  Ok(serde_json::to_string_pretty(&vars)?)
}
