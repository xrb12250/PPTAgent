import asyncio
import os
from typing import Any, Literal

import aiohttp
from appcore import mcp
from fake_useragent import UserAgent

from deeppresenter.utils.constants import MAX_RETRY_INTERVAL, RETRY_TIMES
from deeppresenter.utils.log import info, warning

FAKE_UA = UserAgent()
TAVILY_API_URL = "https://api.tavily.com/search"
DUCKDUCKGO_AVAILABLE = False

# Try to import duckduckgo_search for local/offline search
try:
    from duckduckgo_search import DDGS

    DUCKDUCKGO_AVAILABLE = True
except ImportError:
    pass

# Check if offline mode is enabled via environment variable
OFFLINE_MODE = os.getenv("PPTAGENT_OFFLINE_MODE", "").lower() in ("true", "1", "yes")


async def duckduckgo_search(query: str, max_results: int = 3) -> dict[str, Any]:
    """
    Perform a search using DuckDuckGo (no API key required).
    This runs locally and doesn't require external API services.
    """
    if not DUCKDUCKGO_AVAILABLE:
        raise ImportError(
            "duckduckgo_search is not installed. Install it with: pip install duckduckgo-search"
        )

    def _search():
        with DDGS() as ddgs:
            results = list(ddgs.text(query, max_results=max_results))
            return results

    # Run in executor to avoid blocking
    loop = asyncio.get_event_loop()
    results = await loop.run_in_executor(None, _search)

    return {
        "results": [
            {"url": r.get("href", ""), "content": r.get("body", "")} for r in results
        ]
    }


async def duckduckgo_image_search(query: str, max_results: int = 4) -> dict[str, Any]:
    """
    Search for images using DuckDuckGo (no API key required).
    """
    if not DUCKDUCKGO_AVAILABLE:
        raise ImportError(
            "duckduckgo_search is not installed. Install it with: pip install duckduckgo-search"
        )

    def _search():
        with DDGS() as ddgs:
            results = list(ddgs.images(query, max_results=max_results))
            return results

    loop = asyncio.get_event_loop()
    results = await loop.run_in_executor(None, _search)

    return {
        "images": [
            {"url": r.get("image", ""), "description": r.get("title", "")}
            for r in results
        ]
    }


async def offline_search_placeholder(query: str, max_results: int = 3) -> dict[str, Any]:
    """
    Placeholder for offline mode - returns empty results with a message.
    """
    info(f"Offline mode: Search for '{query}' skipped (no internet access)")
    return {
        "results": [],
        "message": "Search unavailable in offline mode. Please provide content directly.",
    }


async def tavily_request(params: dict) -> dict[str, Any]:
    """发送 Tavily API 请求"""
    headers = {"Content-Type": "application/json", "User-Agent": FAKE_UA.random}

    async with aiohttp.ClientSession() as session:
        async with session.post(
            TAVILY_API_URL, headers=headers, json=params
        ) as response:
            if response.status == 429:
                warning("TAVILY rate limit exceeded, waiting...")
                await asyncio.sleep(MAX_RETRY_INTERVAL)
            if response.status != 200:
                warning(
                    f"TAVILY Error [{response.status}] headers={dict(response.headers)} body={await response.text()}"
                )
            response.raise_for_status()
            return await response.json()


async def search_with_fallback(**kwargs) -> dict[str, Any]:
    """
    Search with multiple fallback options:
    1. Tavily API (if API key is available)
    2. DuckDuckGo (free, no API key needed)
    3. Offline placeholder (if all else fails)
    """
    query = kwargs.get("query", "")
    max_results = kwargs.get("max_results", 3)

    # If in offline mode, return placeholder immediately
    if OFFLINE_MODE:
        return await offline_search_placeholder(query, max_results)

    # Try Tavily first if API key is available
    api_keys = [k for k in [os.getenv("TAVILY_API_KEY"), os.getenv("TAVILY_BACKUP")] if k]

    if api_keys:
        last_error = None
        for idx in range(RETRY_TIMES):
            for api_key in api_keys:
                await asyncio.sleep(min(2**idx - 1, MAX_RETRY_INTERVAL))
                try:
                    params = {**kwargs, "api_key": api_key}
                    return await tavily_request(params)
                except Exception as e:
                    warning(f"TAVILY search error with key {api_key[:16]}...: {e}")
                    last_error = e

        warning(f"TAVILY search failed, falling back to DuckDuckGo: {last_error}")

    # Fallback to DuckDuckGo (no API key required)
    if DUCKDUCKGO_AVAILABLE:
        try:
            info("Using DuckDuckGo for search (no API key required)")
            return await duckduckgo_search(query, max_results)
        except Exception as e:
            warning(f"DuckDuckGo search error: {e}")

    # Final fallback: offline placeholder
    warning("All search methods failed, using offline placeholder")
    return await offline_search_placeholder(query, max_results)


@mcp.tool()
async def search_web(
    query: str,
    max_results: int = 3,
    time_range: Literal["month", "year"] | None = None,
) -> dict:
    """
    Search the web

    Args:
        query: Search keywords
        max_results: Maximum number of search results, default 3
        time_range: Time range filter for search results, can be "month", "year", or None

    Returns:
        dict: Dictionary containing search results
    """
    kwargs = {"query": query, "max_results": max_results, "include_images": False}
    if time_range:
        kwargs["time_range"] = time_range

    result = await search_with_fallback(**kwargs)

    results = [
        {
            "url": item["url"],
            "content": item["content"],
        }
        for item in result.get("results", [])
    ]

    return {
        "query": query,
        "total_results": len(results),
        "results": results,
    }


@mcp.tool()
async def search_images(
    query: str,
) -> dict:
    """
    Search for web images
    """
    # If in offline mode, return empty results
    if OFFLINE_MODE:
        info(f"Offline mode: Image search for '{query}' skipped")
        return {
            "query": query,
            "total_results": 0,
            "images": [],
            "message": "Image search unavailable in offline mode.",
        }

    # Try Tavily first if API keys are available
    api_keys = [k for k in [os.getenv("TAVILY_API_KEY"), os.getenv("TAVILY_BACKUP")] if k]

    if api_keys:
        try:
            result = await search_with_fallback(
                query=query,
                max_results=4,
                include_images=True,
                include_image_descriptions=True,
            )
            images = [
                {
                    "url": img["url"],
                    "description": img["description"],
                }
                for img in result.get("images", [])
            ]
            if images:
                return {
                    "query": query,
                    "total_results": len(images),
                    "images": images,
                }
        except Exception as e:
            warning(f"Tavily image search failed: {e}")

    # Fallback to DuckDuckGo image search
    if DUCKDUCKGO_AVAILABLE:
        try:
            info("Using DuckDuckGo for image search")
            result = await duckduckgo_image_search(query, max_results=4)
            images = result.get("images", [])
            return {
                "query": query,
                "total_results": len(images),
                "images": images,
            }
        except Exception as e:
            warning(f"DuckDuckGo image search failed: {e}")

    return {
        "query": query,
        "total_results": 0,
        "images": [],
        "message": "Image search unavailable.",
    }


if __name__ == "__main__":
    import asyncio

    result = asyncio.run(search_web('Google Gemini model "Gemini 3 Pro" features'))
    print(result)
