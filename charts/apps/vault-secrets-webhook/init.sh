# Get cluster information
KUBE_HOST=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.server}')
KUBE_CA_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 -d)

# Create a long-lived token for token review
REVIEWER_TOKEN=$(kubectl create token default -n default --duration=8760h)

# Configure with full details if not local cluster
# bao write auth/kubernetes/config \
#     kubernetes_host="$KUBE_HOST" \
#     kubernetes_ca_cert="$KUBE_CA_CERT" \
#     token_reviewer_jwt="$REVIEWER_TOKEN" \
#     disable_iss_validation=true

bao write auth/kubernetes/config \
    kubernetes_host="$KUBE_HOST" \
    disable_iss_validation=true

# Create a policy for vault-secrets-webhook
bao policy write vault-secrets-webhook - <<EOF
# Allow reading secrets (primary function)
path "secret/data/*" {
  capabilities = ["read"]
}

path "secret/metadata/*" {
  capabilities = ["read", "list"]
}

path "kv/data/*" {
  capabilities = ["read"]
}

path "kv/metadata/*" {
  capabilities = ["read", "list"]
}

# Standard token operations (from default policy)
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/revoke-self" {
  capabilities = ["update"]
}

path "sys/capabilities-self" {
  capabilities = ["update"]
}

# Cubbyhole access
path "cubbyhole/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF

# Create a named role for vault-secrets-webhook
bao write auth/kubernetes/role/vault-secrets-webhook \
    bound_service_account_names=vault-secrets-webhook \
    bound_service_account_namespaces=openbao \
    policies=vault-secrets-webhook \
    ttl=1h
