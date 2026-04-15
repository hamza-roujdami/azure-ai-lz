"""Key Vault connectivity check — read a test secret via managed identity."""

from azure.identity.aio import DefaultAzureCredential
from azure.keyvault.secrets.aio import SecretClient
from config import FOUNDRY_KV_URL, APP_KV_URL


async def check_foundry_kv() -> str:
    if not FOUNDRY_KV_URL:
        raise ValueError("FOUNDRY_KV_URL not configured")
    credential = DefaultAzureCredential()
    async with credential:
        client = SecretClient(vault_url=FOUNDRY_KV_URL, credential=credential)
        async with client:
            props = []
            async for secret in client.list_properties_of_secrets():
                props.append(secret.name)
                if len(props) >= 3:
                    break
            return f"Foundry KV accessible, {len(props)} secret(s) found"


async def check_app_kv() -> str:
    if not APP_KV_URL:
        raise ValueError("APP_KV_URL not configured")
    credential = DefaultAzureCredential()
    async with credential:
        client = SecretClient(vault_url=APP_KV_URL, credential=credential)
        async with client:
            props = []
            async for secret in client.list_properties_of_secrets():
                props.append(secret.name)
                if len(props) >= 3:
                    break
            return f"App KV accessible, {len(props)} secret(s) found"
