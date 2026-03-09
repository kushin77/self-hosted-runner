VAULT_ADDR={{ with secret "secret/deployment/fields/VAULT_ADDR" }}{{ .Data.data.value }}{{ end }}
VAULT_ROLE={{ with secret "secret/deployment/fields/VAULT_ROLE" }}{{ .Data.data.value }}{{ end }}
AWS_ROLE_TO_ASSUME={{ with secret "secret/deployment/fields/AWS_ROLE_TO_ASSUME" }}{{ .Data.data.value }}{{ end }}
GCP_WORKLOAD_IDENTITY_PROVIDER={{ with secret "secret/deployment/fields/GCP_WORKLOAD_IDENTITY_PROVIDER" }}{{ .Data.data.value }}{{ end }}
