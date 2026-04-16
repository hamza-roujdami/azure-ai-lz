"""AI Landing Zone — Infrastructure Validation App.

FastAPI app that tests connectivity to all deployed services.
Runs on Container Apps using managed identity — zero secrets.
"""

from dataclasses import asdict
from fastapi import FastAPI
from checks import run_check, CheckResult
from checks.keyvault import check_foundry_kv, check_app_kv
from checks.storage import check_storage
from checks.cosmos import check_cosmos
from checks.search import check_search
from checks.foundry import check_foundry
from checks.compass import check_compass_models, check_compass_chat

app = FastAPI(title="AI Landing Zone Health Check", version="1.0.0")


@app.get("/health")
async def health():
    return {"status": "ok", "service": "lz-healthcheck"}


@app.get("/health/keyvault")
async def health_keyvault():
    results = [
        await run_check("foundry-kv", check_foundry_kv),
        await run_check("app-kv", check_app_kv),
    ]
    return [asdict(r) for r in results]


@app.get("/health/storage")
async def health_storage():
    result = await run_check("storage", check_storage)
    return asdict(result)


@app.get("/health/cosmos")
async def health_cosmos():
    result = await run_check("cosmos", check_cosmos)
    return asdict(result)


@app.get("/health/search")
async def health_search():
    result = await run_check("search", check_search)
    return asdict(result)


@app.get("/health/foundry")
async def health_foundry():
    result = await run_check("foundry", check_foundry)
    return asdict(result)


@app.get("/health/compass")
async def health_compass():
    results = [
        await run_check("compass-models", check_compass_models),
        await run_check("compass-chat", check_compass_chat),
    ]
    return [asdict(r) for r in results]


@app.get("/health/all")
async def health_all():
    checks = [
        run_check("foundry-kv", check_foundry_kv),
        run_check("app-kv", check_app_kv),
        run_check("storage", check_storage),
        run_check("cosmos", check_cosmos),
        run_check("search", check_search),
        run_check("foundry", check_foundry),
        run_check("compass-models", check_compass_models),
        run_check("compass-chat", check_compass_chat),
    ]
    import asyncio
    results = await asyncio.gather(*checks)
    passed = sum(1 for r in results if r.status == "pass")
    failed = sum(1 for r in results if r.status == "fail")
    skipped = sum(1 for r in results if r.status == "skip")
    return {
        "summary": {"total": len(results), "passed": passed, "failed": failed, "skipped": skipped},
        "checks": [asdict(r) for r in results],
    }
