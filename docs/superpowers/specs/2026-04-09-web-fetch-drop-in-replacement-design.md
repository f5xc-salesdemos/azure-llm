# Web Fetch Drop-in Replacement Design

## Context

The Claude Code proxy on the Azure VM workstation intercepts `web_fetch` tool calls and routes them to a local Firecrawl instance instead of Anthropic's native server-side processing. The current implementation returns raw Firecrawl markdown as `text/plain`, producing a wall of unformatted text. Anthropic's native `web_fetch` uses a Haiku model to process and clean the fetched content before returning it, producing well-structured markdown with proper headings, paragraphs, and line breaks.

The proxy must be a **perfect drop-in transparent replacement** -- identical response envelope format and LLM-processed content that matches the quality of Anthropic's native web_fetch output.

## Architecture

### Component: `FirecrawlFetchProvider` (modified)

**File:** `src/services/fetch/firecrawl_fetch.py`

Add LLM content processing after Firecrawl returns raw markdown:

1. Firecrawl scrapes URL -> raw markdown
2. Call local vLLM (`large-llm` model via OpenAI-compatible API) with a processing prompt
3. The prompt instructs the LLM to **reformat and clean** the content (not summarize) -- preserving all information but adding proper markdown structure
4. Use high-temperature reasoning (`temperature: 0.6`) for quality reformatting
5. Return processed content in the Anthropic `web_fetch_result` envelope

**LLM Config:** The provider constructor accepts `openai_base_url`, `openai_api_key`, and `model` parameters. These are sourced from the existing proxy config (`config.openai_base_url`, `config.openai_api_key`, `config.big_model`).

**Processing Prompt:**
```
You are a web content processor. Reformat the following web page content into clean, well-structured markdown. Preserve ALL information -- do not summarize or omit content. Apply proper markdown formatting: headings, paragraphs, lists, code blocks, and line breaks. Remove navigation elements, ads, and boilerplate. Return only the reformatted content with no preamble.
```

**Fallback:** If the LLM call fails (timeout, error), return the raw Firecrawl markdown rather than failing the entire fetch. Log a warning.

### Component: Lifespan initialization (modified)

**File:** `src/main.py`

Pass LLM config to `FirecrawlFetchProvider` during initialization:

```python
fetch_prov = FirecrawlFetchProvider(
    firecrawl_url,
    openai_base_url=config.openai_base_url,
    openai_api_key=config.openai_api_key,
    model=config.big_model,
)
```

### Response Envelope (verified, no changes needed)

The existing envelope structure in `firecrawl_fetch.py` already matches Anthropic's spec:

```json
{
  "type": "web_fetch_result",
  "url": "<url>",
  "content": {
    "type": "document",
    "source": {
      "type": "text",
      "media_type": "text/plain",
      "data": "<processed markdown>"
    },
    "title": "<page title>",
    "citations": {"enabled": true}
  },
  "retrieved_at": "<ISO8601>"
}
```

### No changes to: endpoints.py, response_converter.py, request_converter.py, constants.py

The routing, interception, and SSE streaming logic is already correct. Only the content quality (inside `data` field) needs improvement.

## Test Plan (TDD -- tests written first)

**New file:** `tests/test_web_fetch_spec.py`

Following the pattern established by `tests/test_web_search_spec.py`:

### Test Group 1: Response Envelope Format
- `test_fetch_result_has_correct_type` -- result dict has `type: "web_fetch_result"`
- `test_fetch_result_has_url` -- result contains the original URL
- `test_fetch_result_has_document_content` -- content has `type: "document"` with `source.type: "text"`
- `test_fetch_result_has_title` -- title from metadata is present
- `test_fetch_result_has_retrieved_at` -- ISO8601 timestamp present
- `test_fetch_result_has_citations_enabled` -- citations block present

### Test Group 2: LLM Content Processing
- `test_llm_called_with_raw_content` -- LLM receives raw Firecrawl markdown
- `test_llm_response_used_as_content` -- processed content replaces raw markdown
- `test_llm_failure_falls_back_to_raw` -- on LLM error, raw content is returned
- `test_llm_timeout_falls_back_to_raw` -- on timeout, raw content is returned

### Test Group 3: Non-streaming web_fetch
- `test_single_fetch_tool_blocks_before_text` -- order: server_tool_use, web_fetch_tool_result, text
- `test_multiple_fetches_all_present` -- multiple fetch URLs produce paired blocks
- `test_tool_use_ids_link_pairs` -- server_tool_use id matches result's tool_use_id
- `test_no_text_only_tool_blocks` -- when no text content, only tool blocks appear

### Test Group 4: Streaming web_fetch
- `test_server_tool_use_has_input_empty_dict` -- SSE block_start includes `input: {}`
- `test_fetch_result_block_emitted_after_tool_stop` -- result block follows tool block
- `test_domain_filters_passed_to_provider` -- allowed/blocked domains forwarded

### Test Group 5: Error Handling
- `test_error_result_format` -- error dict matches `{"type": "web_fetch_tool_error", "error_code": "..."}`
- `test_404_returns_url_not_accessible` -- HTTP 404 maps to correct error code
- `test_domain_blocked_returns_url_not_allowed` -- blocked domain returns correct error

### Test Group 6: Content Size
- `test_content_capped_at_100k` -- raw content over 100K chars is truncated before LLM processing

**New file:** `tests/conftest.py` additions

Add `FakeFetchProvider` class mirroring `FakeSearchProvider`:
- Configurable results and errors
- Tracks last call parameters (URL, domain filters)

## Verification

1. Run all tests on workstation: `cd /opt/claude-code-proxy && ./venv/bin/pytest tests/test_web_fetch_spec.py -v`
2. Run full test suite to verify no regressions: `./venv/bin/pytest -v`
3. Restart proxy: `sudo systemctl restart claude-code-proxy`
4. Test via Claude Code CLI on workstation:
   - `web_fetch https://example.com` -- verify clean formatted output
   - `web_fetch https://endoflife.date/api/big-ip.json` -- verify JSON content handled
   - `web_fetch https://httpbin.org/html` -- verify HTML content cleaned
   - Compare output quality against native Anthropic web_fetch results captured earlier
