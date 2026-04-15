"""Compass / APIM connectivity check — test LLM call via APIM gateway."""

import httpx
from config import APIM_COMPASS_URL, APIM_SUBSCRIPTION_KEY


async def check_compass_models() -> str:
    """Test ListDeployments — returns available models from APIM."""
    if not APIM_COMPASS_URL:
        raise ValueError("APIM_COMPASS_URL not configured — Compass not enabled")
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.get(
            f"{APIM_COMPASS_URL}/deployments",
            headers={"api-key": APIM_SUBSCRIPTION_KEY},
        )
        resp.raise_for_status()
        models = [m["name"] for m in resp.json().get("value", [])]
        return f"APIM ListDeployments OK — models: {models}"


async def check_compass_chat() -> str:
    """Test ChatCompletions — sends a test prompt to Compass via APIM."""
    if not APIM_COMPASS_URL:
        raise ValueError("APIM_COMPASS_URL not configured — Compass not enabled")
    if not APIM_SUBSCRIPTION_KEY:
        raise ValueError("APIM_SUBSCRIPTION_KEY not configured")
    # Use first available model
    async with httpx.AsyncClient(timeout=60) as client:
        list_resp = await client.get(
            f"{APIM_COMPASS_URL}/deployments",
            headers={"api-key": APIM_SUBSCRIPTION_KEY},
        )
        list_resp.raise_for_status()
        models = list_resp.json().get("value", [])
        if not models:
            raise ValueError("No models available in APIM")
        model = models[0]["name"]

        chat_resp = await client.post(
            f"{APIM_COMPASS_URL}/deployments/{model}/chat/completions",
            headers={
                "api-key": APIM_SUBSCRIPTION_KEY,
                "Content-Type": "application/json",
            },
            json={
                "messages": [{"role": "user", "content": "Say hello in one word."}],
                "max_tokens": 10,
            },
        )
        chat_resp.raise_for_status()
        data = chat_resp.json()
        reply = data["choices"][0]["message"]["content"]
        usage = data.get("usage", {})
        return f"Compass chat OK — model: {model}, reply: '{reply}', tokens: {usage}"
