"""Storage Account connectivity check — upload and download a test blob."""

from azure.identity.aio import DefaultAzureCredential
from azure.storage.blob.aio import BlobServiceClient
from config import STORAGE_ACCOUNT


CONTAINER = "lz-healthcheck"
BLOB_NAME = "healthcheck.txt"
BLOB_CONTENT = b"landing-zone-healthcheck"


async def check_storage() -> str:
    if not STORAGE_ACCOUNT:
        raise ValueError("STORAGE_ACCOUNT not configured")
    url = f"https://{STORAGE_ACCOUNT}.blob.core.windows.net"
    credential = DefaultAzureCredential()
    async with credential:
        client = BlobServiceClient(account_url=url, credential=credential)
        async with client:
            container = client.get_container_client(CONTAINER)
            if not await container.exists():
                await container.create_container()
            blob = container.get_blob_client(BLOB_NAME)
            await blob.upload_blob(BLOB_CONTENT, overwrite=True)
            data = await blob.download_blob()
            content = await data.readall()
            assert content == BLOB_CONTENT
            return f"Storage blob write/read OK ({STORAGE_ACCOUNT})"
