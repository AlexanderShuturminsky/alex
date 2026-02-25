"""
Integration tests for the Flask API.

Write tests that exercise the HTTP endpoints end-to-end (but with mocked
external services like LLM and HTTP clients). These should test:

- Template CRUD (create, get, list, delete)
- Template search and filtering
- Template cloning (happy path, rate limiting, permissions)
- Flow execution via API (run, get status, cancel)
- Auth (missing X-User-Id header)
- Error responses (404, 403, 400, 429)
- Serialization (response shapes match frontend expectations)
"""

import pytest
import json
from unittest.mock import MagicMock

from src.app import create_app
from src.template_service import TemplateService
from src.flow_runner import FlowRunner
from src.models import (
    FlowTemplate, NodeConfig, NodeType, Edge, TemplateCategory,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def template_service():
    """Fresh template service per test."""
    return TemplateService()


@pytest.fixture
def llm_client():
    client = MagicMock()
    client.complete.return_value = MagicMock(
        text="AI summary result",
        usage={"input_tokens": 15, "output_tokens": 25},
    )
    return client


@pytest.fixture
def http_client():
    client = MagicMock()
    resp = MagicMock()
    resp.status_code = 200
    resp.json.return_value = {"ok": True}
    resp.text = "<html>scraped</html>"
    resp.headers = {"content-type": "application/json"}
    client.request.return_value = resp
    return client


@pytest.fixture
def flow_runner(llm_client, http_client):
    return FlowRunner(llm_client=llm_client, http_client=http_client)


@pytest.fixture
def app(template_service, flow_runner):
    """Create a test Flask app."""
    app = create_app(template_service=template_service, flow_runner=flow_runner)
    app.config["TESTING"] = True
    return app


@pytest.fixture
def client(app):
    """Flask test client."""
    return app.test_client()


@pytest.fixture
def auth_headers():
    """Default auth headers."""
    return {"X-User-Id": "user-1", "Content-Type": "application/json"}


def make_template_payload(name="Test Template", category="marketing", **overrides):
    """Helper to create a valid template creation payload."""
    payload = {
        "name": name,
        "description": "A test template for automation",
        "category": category,
        "nodes": [
            {
                "nodeId": "trigger-1",
                "nodeType": "trigger",
                "label": "Webhook Trigger",
                "params": {"trigger_type": "webhook"},
            },
            {
                "nodeId": "ai-1",
                "nodeType": "ai_transform",
                "label": "AI Summarize",
                "params": {
                    "model": "claude-sonnet-4-20250514",
                    "prompt_template": "Summarize: {text}",
                    "max_tokens": 256,
                },
            },
            {
                "nodeId": "output-1",
                "nodeType": "output",
                "label": "Slack Output",
                "params": {"destination": "slack"},
            },
        ],
        "edges": [
            {"sourceNodeId": "trigger-1", "targetNodeId": "ai-1"},
            {"sourceNodeId": "ai-1", "targetNodeId": "output-1"},
        ],
        "tags": ["test", "automation"],
        "isPublic": True,
    }
    payload.update(overrides)
    return payload


# ---------------------------------------------------------------------------
# Your integration tests go here
# ---------------------------------------------------------------------------
