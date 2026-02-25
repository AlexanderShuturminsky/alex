"""
Executes individual nodes within a flow.
Handles retries, timeouts, and execution recording.
"""

import time
import logging
from typing import Any

from src.models import NodeConfig, NodeType

logger = logging.getLogger(__name__)

DEFAULT_TIMEOUT = 30
MAX_RETRIES = 3


class NodeExecutionError(Exception):
    def __init__(self, node_id: str, message: str):
        self.node_id = node_id
        super().__init__(f"Node '{node_id}' execution failed: {message}")


class NodeTimeoutError(NodeExecutionError):
    pass


class NodeExecutionResult:
    def __init__(
        self,
        node_id: str,
        output: dict[str, Any],
        execution_time_ms: float,
        retries: int = 0,
    ):
        self.node_id = node_id
        self.output = output
        self.execution_time_ms = execution_time_ms
        self.retries = retries
        self.success = True


def execute_node(
    node: NodeConfig,
    input_data: dict[str, Any],
    llm_client=None,
    http_client=None,
    timeout: int = DEFAULT_TIMEOUT,
) -> NodeExecutionResult:
    """Execute a single node with input data and return the result."""
    start = time.time()

    handlers = {
        NodeType.AI_TRANSFORM: _execute_ai_transform,
        NodeType.API_CALL: _execute_api_call,
        NodeType.CONDITIONAL: _execute_conditional,
        NodeType.OUTPUT: _execute_output,
        NodeType.TRIGGER: _execute_trigger,
        NodeType.WEB_SCRAPER: _execute_web_scraper,
        NodeType.DATA_TRANSFORM: _execute_data_transform,
    }

    handler = handlers.get(node.node_type)
    if not handler:
        raise NodeExecutionError(node.node_id, f"Unknown node type: {node.node_type}")

    last_error = None
    retries = 0

    for attempt in range(MAX_RETRIES):
        try:
            if node.node_type == NodeType.AI_TRANSFORM:
                output = handler(node, input_data, llm_client)
            elif node.node_type in (NodeType.API_CALL, NodeType.WEB_SCRAPER):
                output = handler(node, input_data, http_client)
            else:
                output = handler(node, input_data)

            elapsed_ms = (time.time() - start) * 1000
            if elapsed_ms > timeout * 1000:
                raise NodeTimeoutError(
                    node.node_id,
                    f"Execution exceeded timeout of {timeout}s",
                )

            return NodeExecutionResult(
                node_id=node.node_id,
                output=output,
                execution_time_ms=elapsed_ms,
                retries=retries,
            )
        except (NodeTimeoutError, NodeExecutionError):
            raise
        except Exception as e:
            last_error = e
            retries = attempt + 1
            logger.warning(f"Node '{node.node_id}' attempt {attempt + 1} failed: {e}")
            if attempt < MAX_RETRIES - 1:
                time.sleep(0.1 * (2**attempt))

    raise NodeExecutionError(
        node.node_id,
        f"Failed after {MAX_RETRIES} retries. Last error: {last_error}",
    )


def _execute_ai_transform(node, input_data, llm_client):
    if llm_client is None:
        raise NodeExecutionError(node.node_id, "LLM client not configured")

    prompt_template = node.params.get("prompt_template", "")
    model = node.params.get("model", "claude-sonnet-4-20250514")

    try:
        rendered_prompt = prompt_template.format(**input_data)
    except KeyError as e:
        raise NodeExecutionError(
            node.node_id, f"Prompt template references missing variable: {e}"
        )

    response = llm_client.complete(
        model=model,
        prompt=rendered_prompt,
        max_tokens=node.params.get("max_tokens", 1024),
        temperature=node.params.get("temperature", 0.0),
    )

    return {"result": response.text, "model": model, "tokens_used": response.usage}


def _execute_api_call(node, input_data, http_client):
    if http_client is None:
        raise NodeExecutionError(node.node_id, "HTTP client not configured")

    url = node.params["url"]
    method = node.params["method"].upper()

    try:
        url = url.format(**input_data)
    except KeyError:
        pass

    body = node.params.get("body")
    if body and isinstance(body, str):
        try:
            body = body.format(**input_data)
        except KeyError:
            pass

    headers = node.params.get("headers", {})
    response = http_client.request(
        method=method, url=url, headers=headers,
        json=body if method in ("POST", "PUT", "PATCH") else None,
    )

    if response.status_code >= 400:
        raise NodeExecutionError(
            node.node_id,
            f"API call returned {response.status_code}: {response.text[:200]}",
        )

    content_type = response.headers.get("content-type", "")
    return {
        "status_code": response.status_code,
        "body": response.json() if "application/json" in content_type else response.text,
        "headers": dict(response.headers),
    }


def _execute_web_scraper(node, input_data, http_client):
    if http_client is None:
        raise NodeExecutionError(node.node_id, "HTTP client not configured")

    target_url = node.params["target_url"]
    try:
        target_url = target_url.format(**input_data)
    except KeyError:
        pass

    response = http_client.request(method="GET", url=target_url, headers={})

    if response.status_code >= 400:
        raise NodeExecutionError(
            node.node_id, f"Scrape failed with status {response.status_code}"
        )

    return {
        "raw_html": response.text,
        "url": target_url,
        "selectors": node.params.get("selectors", []),
    }


def _execute_conditional(node, input_data):
    expression = node.params.get("condition_expression", "")
    safe_globals = {"__builtins__": {}}
    try:
        result = eval(expression, safe_globals, input_data)
    except Exception as e:
        raise NodeExecutionError(node.node_id, f"Condition evaluation failed: {e}")
    return {"condition_result": bool(result), "branch": "true" if result else "false"}


def _execute_output(node, input_data):
    destination = node.params.get("destination", "")
    return {"destination": destination, "payload": input_data}


def _execute_trigger(node, input_data):
    return {"triggered": True, "trigger_data": input_data}


def _execute_data_transform(node, input_data):
    expression = node.params.get("transform_expression", "")
    safe_globals = {"__builtins__": {}}
    try:
        result = eval(expression, safe_globals, input_data)
    except Exception as e:
        raise NodeExecutionError(node.node_id, f"Transform failed: {e}")
    return {"transformed": result}
