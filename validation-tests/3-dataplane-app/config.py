"""Configuration — all from environment variables, zero secrets."""

import os


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


# AI Foundry
FOUNDRY_ENDPOINT = env("FOUNDRY_ENDPOINT")  # https://ais-csd-dev-swc-001.services.ai.azure.com
PROJECT_NAME = env("PROJECT_NAME")  # proj-csd-default-dev-swc-001

# Cosmos DB
COSMOS_ENDPOINT = env("COSMOS_ENDPOINT")  # https://cosmos-csd-fnd-dev-swc-001.documents.azure.com:443/

# Storage
STORAGE_ACCOUNT = env("STORAGE_ACCOUNT")  # stcsdfnddevswc001

# AI Search
SEARCH_ENDPOINT = env("SEARCH_ENDPOINT")  # https://srch-csd-dev-swc-001.search.windows.net

# Key Vaults
FOUNDRY_KV_URL = env("FOUNDRY_KV_URL")  # https://kv-csd-fnd-dev-swc-001.vault.azure.net
APP_KV_URL = env("APP_KV_URL")  # https://kv-csd-app-dev-swc-001.vault.azure.net

# APIM (optional — only when Compass is configured)
APIM_COMPASS_URL = env("APIM_COMPASS_URL")  # https://apim-cpx-dev-swc-002.azure-api.net/compass
APIM_SUBSCRIPTION_KEY = env("APIM_SUBSCRIPTION_KEY")
