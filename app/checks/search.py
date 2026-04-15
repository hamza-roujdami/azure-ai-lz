"""AI Search connectivity check — create a test index and query it."""

from azure.identity.aio import DefaultAzureCredential
from azure.search.documents.indexes.aio import SearchIndexClient
from azure.search.documents.indexes.models import SearchIndex, SimpleField, SearchFieldDataType
from azure.search.documents.aio import SearchClient
from config import SEARCH_ENDPOINT


INDEX_NAME = "lz-healthcheck"


async def check_search() -> str:
    if not SEARCH_ENDPOINT:
        raise ValueError("SEARCH_ENDPOINT not configured")
    credential = DefaultAzureCredential()
    async with credential:
        index_client = SearchIndexClient(endpoint=SEARCH_ENDPOINT, credential=credential)
        async with index_client:
            index = SearchIndex(
                name=INDEX_NAME,
                fields=[
                    SimpleField(name="id", type=SearchFieldDataType.String, key=True),
                    SimpleField(name="status", type=SearchFieldDataType.String, filterable=True),
                ],
            )
            await index_client.create_or_update_index(index)
            names = [idx.name async for idx in index_client.list_indexes()]
            assert INDEX_NAME in names
            return f"AI Search index create/list OK ({len(names)} index(es))"
