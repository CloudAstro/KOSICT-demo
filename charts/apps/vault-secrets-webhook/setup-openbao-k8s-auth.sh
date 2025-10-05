#!/bin/bash

# Simple OpenBao Kubernetes Auth Setup
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🔐 OpenBao Kubernetes Auth Setup${NC}"

# Get inputs
read -p "OpenBao URL [https://admin.cloudastro.io](https://admin.cloudastro.io): " BAO_ADDR
BAO_ADDR=${BAO_ADDR:-https://admin.cloudastro.io}

echo -n "OpenBao Token: "
read -s BAO_TOKEN
echo

read -p "Is OpenBao running inside cluster? (y/n) [y]: " INTERNAL
INTERNAL=${INTERNAL:-y}

read -p "Service account name [vault-secrets-webhook]: " SA_NAME
SA_NAME=${SA_NAME:-vault-secrets-webhook}

read -p "Namespace [vault-secrets-webhook]: " SA_NAMESPACE
SA_NAMESPACE=${SA_NAMESPACE:-vault-secrets-webhook}

read -p "Enable KV store? (y/n) [y]: " ENABLE_KV
ENABLE_KV=${ENABLE_KV:-y}

read -p "Create db secret? (y/n) [y]: " CREATE_DB_SECRET
CREATE_DB_SECRET=${CREATE_DB_SECRET:-y}

# Setup
export BAO_ADDR BAO_TOKEN

echo -e "${YELLOW}Setting up...${NC}"

# Enable KV if requested
if [[ $ENABLE_KV == "y" ]]; then
    bao secrets enable -path=secret kv-v2 2>/dev/null || echo "KV already enabled"
fi

# Enable auth
bao auth enable kubernetes 2>/dev/null || echo "Kubernetes auth already enabled"

# Configure auth
if [[ $INTERNAL == "y" ]]; then
    KUBE_HOST="https://kubernetes.default.svc.cluster.local"
    bao write auth/kubernetes/config \
        kubernetes_host="$KUBE_HOST" \
        disable_iss_validation=true
else
    KUBE_HOST=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.server}')
    KUBE_CA_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 -d)
    REVIEWER_TOKEN=$(kubectl create token default -n default --duration=8760h)
    
    bao write auth/kubernetes/config \
        kubernetes_host="$KUBE_HOST" \
        kubernetes_ca_cert="$KUBE_CA_CERT" \
        token_reviewer_jwt="$REVIEWER_TOKEN" \
        disable_iss_validation=true
fi

# Create policy
bao policy write vault-secrets-webhook - <<EOF
path "secret/data/*" {
  capabilities = ["create", "update","read", "list"]
}
path "secret/metadata/*" {
  capabilities = ["create", "update", "delete","read", "list"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
path "sys/capabilities-self" {
  capabilities = ["update"]
}
path "cubbyhole/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF

# Create role
bao write auth/kubernetes/role/vault-secrets-webhook \
    bound_service_account_names="$SA_NAME" \
    bound_service_account_namespaces="$SA_NAMESPACE" \
    policies=vault-secrets-webhook \
    ttl=1h

generate_password() {
    openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 32
}

# Secrets to create with generated passwords
SECRETS_TO_UPDATE=(
    "secret/db/gitlab:gitlab"
    "secret/db/harbor:harbor"
    "secret/db/keycloak:keycloak"
)

# Create each secret with a generated password
if [[ $CREATE_DB_SECRET == "y" ]]; then
  for entry in "${SECRETS_TO_UPDATE[@]}"; do
      secret_path="${entry%%:*}"  # Extract path before ':'
      user="${entry##*:}"         # Extract user after ':'
      password=$(generate_password)
      echo -e "${YELLOW}Creating secret ${secret_path} with generated password for user ${user}${NC}"
      bao kv put "${secret_path}" password="${password}"
      echo -e "${GREEN}✅ Secret created at ${secret_path}${NC}"
  done
fi


# Test auth
echo -e "${YELLOW}Testing authentication...${NC}"
if bao write auth/kubernetes/login \
    role=vault-secrets-webhook \
    jwt="$(kubectl create token "$SA_NAME" -n "$SA_NAMESPACE" --duration=1h)" >/dev/null; then
    echo -e "${GREEN}✅ Authentication successful!${NC}"
else
    echo -e "${RED}❌ Authentication failed!${NC}"
    exit 1
fi

echo -e "${GREEN}🎉 Setup complete!${NC}"
echo
echo "Configuration for vault-secrets-webhook:"
echo "  env.VAULT_ADDR: \"$BAO_ADDR\""
echo "  env.VAULT_AUTH_METHOD: \"kubernetes\""
echo "  env.VAULT_PATH: \"kubernetes\""
echo "  env.VAULT_ROLE: \"vault-secrets-webhook\""
