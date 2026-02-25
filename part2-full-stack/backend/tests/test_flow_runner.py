"""
Unit tests for FlowRunner.

Write tests for the flow execution engine. Focus on:
- Flow validation (cycles, missing nodes, empty flows)
- Topological sort / execution order
- Data passing between nodes
- Node type dispatch (AI, API, conditional, output, trigger, web_scraper, data_transform)
- Error handling (stop_on_error=True vs False)
- Conditional branching (skip logic)
- Cancellation
"""

import pytest
from unittest.mock import MagicMock

from src.models import Flow, FlowRun, NodeConfig, NodeType, Edge, RunStatus
from src.flow_runner import FlowRunner, FlowValidationError


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def make_node(node_id: str, node_type: NodeType = NodeType.OUTPUT, **params):
    defaults = {
        NodeType.TRIGGER: {"trigger_type": "webhook"},
        NodeType.AI_TRANSFORM: {
            "model": "claude-sonnet-4-20250514",
            "prompt_template": "Summarize: {text}",
            "max_tokens": 256,
        },
        NodeType.API_CALL: {
            "url": "https://api.example.com/data",
            "method": "POST",
            "body": '{{"text": "{text}"}}',
            "headers": {"Authorization": "Bearer fake"},
        },
        NodeType.CONDITIONAL: {"condition_expression": "score > 50"},
        NodeType.OUTPUT: {"destination": "slack"},
        NodeType.WEB_SCRAPER: {
            "target_url": "https://example.com/{page}",
            "selectors": [".title", ".content"],
        },
        NodeType.DATA_TRANSFORM: {"transform_expression": "[x * 2 for x in items]"},
    }
    merged = {**defaults.get(node_type, {}), **params}
    return NodeConfig(node_id=node_id, node_type=node_type, label=node_id, params=merged)


def make_flow(nodes: list[NodeConfig], edges: list[Edge] | None = None, **kwargs):
    return Flow(
        flow_id=kwargs.get("flow_id", "test-flow"),
        name=kwargs.get("name", "Test Flow"),
        nodes=nodes,
        edges=edges or [],
        owner_id=kwargs.get("owner_id", "user-1"),
    )


def make_run(flow_id: str = "test-flow", **kwargs):
    return FlowRun(
        run_id=kwargs.get("run_id", "run-1"),
        flow_id=flow_id,
        owner_id=kwargs.get("owner_id", "user-1"),
        trigger_data=kwargs.get("trigger_data", {}),
    )


def mock_llm(text="Mock response", usage=None):
    client = MagicMock()
    client.complete.return_value = MagicMock(
        text=text, usage=usage or {"input_tokens": 10, "output_tokens": 20},
    )
    return client


def mock_http(status_code=200, json_body=None, text="<html></html>"):
    client = MagicMock()
    resp = MagicMock()
    resp.status_code = status_code
    resp.json.return_value = json_body or {"ok": True}
    resp.text = text
    resp.headers = {"content-type": "application/json"}
    client.request.return_value = resp
    return client


# ---------------------------------------------------------------------------
# Your unit tests go here
# ---------------------------------------------------------------------------
