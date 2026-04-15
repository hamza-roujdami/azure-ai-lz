"""AI Foundry connectivity check — verify project is accessible via SDK."""

from azure.identity.aio import DefaultAzureCredential
from azure.ai.projects.aio import AIProjectClient
from config import FOUNDRY_ENDPOINT, PROJECT_NAME


async def check_foundry() -> str:
    if not FOUNDRY_ENDPOINT:
        raise ValueError("FOUNDRY_ENDPOINT not configured")
    credential = DefaultAzureCredential()
    async with credential:
        client = AIProjectClient(
            endpoint=FOUNDRY_ENDPOINT,
            credential=credential,
        )
        async with client:
            props = await client.get_project()
            name = props.get("name", "unknown")
            return f"Foundry project accessible ({name})"
