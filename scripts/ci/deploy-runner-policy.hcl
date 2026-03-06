path "secret/data/runnercloud/deploy-ssh-key" {
  capabilities = ["read"]
}
path "secret/metadata/runnercloud/deploy-ssh-key" {
  capabilities = ["read"]
}
path "secret/data/runnercloud/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/runnercloud/*" {
  capabilities = ["read", "list"]
}
