#!/bin/bash

# Arguments
KEYVAULT_NAME=$1
PR_ID=$2
SQL_SERVER=$3
SQL_USER_NAME=$4
SQL_USER_PASSWORD=$5
JWT_SECRET_NAME=$6
APP_CONFIG_NAME=${7:-nis-developers-aac}  # Default value if not provided
# Function to extract base URI from secret identifier
get_base_uri() {
  echo "$1" | sed 's/\(.*\)\/[a-f0-9]\{32\}/\1/'
}

# Set ConnectionString secret
secret_identifier=$(az keyvault secret set --vault-name "$KEYVAULT_NAME" \
  --name "Feature-$PR_ID-ConnectionString" \
  --value "data source=$SQL_SERVER,1433;initial catalog=FEATURE_$PR_ID;User Id=$SQL_USER_NAME;Password=$SQL_USER_PASSWORD;Column Encryption Setting=enabled;Application Name=Nis;" \
  --query id -o tsv)

base_uri=$(get_base_uri "$secret_identifier")

az appconfig kv set-keyvault -n "$APP_CONFIG_NAME" \
  --key ConnectionString \
  --label "Feature-$PR_ID" \
  --secret-identifier "$base_uri" --yes

# Set ElasticPrefix secret
secret_identifier=$(az keyvault secret set --vault-name "$KEYVAULT_NAME" \
  --name "Feature-$PR_ID-ElasticPrefix" \
  --value "feature_$PR_ID" \
  --query id -o tsv)

base_uri=$(get_base_uri "$secret_identifier")

az appconfig kv set-keyvault -n "$APP_CONFIG_NAME" \
  --key Elastic:Prefix \
  --label "Feature-$PR_ID" \
  --secret-identifier "$base_uri" --yes

# Set RedisPrefix secret
secret_identifier=$(az keyvault secret set --vault-name "$KEYVAULT_NAME" \
  --name "Feature-$PR_ID-RedisPrefix" \
  --value "Feature_$PR_ID" \
  --query id -o tsv)

base_uri=$(get_base_uri "$secret_identifier")

az appconfig kv set-keyvault -n "$APP_CONFIG_NAME" \
  --key Redis:Prefix \
  --label "Feature-$PR_ID" \
  --secret-identifier "$base_uri" --yes

# Set HostingEnvironment secret
secret_identifier=$(az keyvault secret set --vault-name "$KEYVAULT_NAME" \
  --name "Feature-$PR_ID-HostingEnvironment" \
  --value "FEATURE\\$PR_ID" \
  --query id -o tsv)

base_uri=$(get_base_uri "$secret_identifier")

az appconfig kv set-keyvault -n "$APP_CONFIG_NAME" \
  --key Logging:Properties:HostingEnvironment \
  --label "Feature-$PR_ID" \
  --secret-identifier "$base_uri" --yes

# Set JWT secret
secret_identifier=$(az keyvault secret set --vault-name "$KEYVAULT_NAME" \
  --name "Feature-$PR_ID-JwtSecret" \
  --value "$JWT_SECRET_NAME" \
  --query id -o tsv)

base_uri=$(get_base_uri "$secret_identifier")

az appconfig kv set-keyvault -n "$APP_CONFIG_NAME" \
  --key Security:Jwt:Secret \
  --label "Feature-$PR_ID" \
  --secret-identifier "$base_uri" --yes
# we need to set the Secret key as well for compatibility
az appconfig kv set-keyvault -n "$APP_CONFIG_NAME" \
  --key Secret \
  --label "Feature-$PR_ID" \
  --secret-identifier "$base_uri" --yes
