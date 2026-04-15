"""Cosmos DB connectivity check — write and read a test document."""

from azure.identity.aio import DefaultAzureCredential
from azure.cosmos.aio import CosmosClient
from config import COSMOS_ENDPOINT
import uuid


DATABASE = "lz-healthcheck"
CONTAINER = "checks"


async def check_cosmos() -> str:
    if not COSMOS_ENDPOINT:
        raise ValueError("COSMOS_ENDPOINT not configured")
    credential = DefaultAzureCredential()
    async with credential:
        client = CosmosClient(COSMOS_ENDPOINT, credential=credential)
        async with client:
            db = await client.create_database_if_not_exists(DATABASE)
            container = await db.create_container_if_not_exists(
                id=CONTAINER, partition_key={"paths": ["/id"], "kind": "Hash"}
            )
            doc_id = str(uuid.uuid4())
            doc = {"id": doc_id, "type": "healthcheck", "status": "ok"}
            await container.create_item(doc)
            read_doc = await container.read_item(doc_id, partition_key=doc_id)
            assert read_doc["status"] == "ok"
            await container.delete_item(doc_id, partition_key=doc_id)
            return f"Cosmos write/read/delete OK ({COSMOS_ENDPOINT.split('//')[1].split('.')[0]})"
