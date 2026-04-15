"""Shared check result model."""

from dataclasses import dataclass, field
import time
from typing import Callable, Awaitable


@dataclass
class CheckResult:
    name: str
    status: str = "skip"  # pass, fail, skip
    message: str = ""
    latency_ms: float = 0


async def run_check(name: str, func: Callable[[], Awaitable[str]]) -> CheckResult:
    start = time.monotonic()
    try:
        msg = await func()
        elapsed = (time.monotonic() - start) * 1000
        return CheckResult(name=name, status="pass", message=msg, latency_ms=round(elapsed, 1))
    except Exception as e:
        elapsed = (time.monotonic() - start) * 1000
        return CheckResult(name=name, status="fail", message=str(e), latency_ms=round(elapsed, 1))
