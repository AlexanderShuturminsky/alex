"""Tests for node execution."""

import pytest
from unittest.mock import MagicMock, patch

from src.models import NodeConfig, NodeType
from src.node_executor import (
    execute_node,
    NodeExecutionError,
    NodeTimeoutError,
    NodeExecutionResult,
    MAX_RETRIES,
)


def _ai_node(node_id="ai-1"):
    return NodeConfig(
        node_id=node_id, node_type=NodeType.AI_TRANSFORM, label="Summarize",
        params={"model": "claude-sonnet-4-20250514", "prompt_template": "Summarize: {text}", "max_tokens": 512},
    )


def _api_node(node_id="api-1"):
    return NodeConfig(
        node_id=node_id, node_type=NodeType.API_CALL, label="Slack",
        params={"url": "https://api.example.com", "method": "POST", "body": '{{"msg": "{text}"}}', "headers": {}},
    )


def _mock_llm(text="response", usage=None):
    m = MagicMock()
    m.complete.return_value = MagicMock(text=text, usage=usage or {"input": 10, "output": 20})
    return m


def _mock_http(status=200, json_data=None):
    m = MagicMock()
    resp = MagicMock()
    resp.status_code = status
    resp.json.return_value = json_data or {"ok": True}
    resp.text = "response body"
    resp.headers = {"content-type": "application/json"}
    m.request.return_value = resp
    return m


class TestNodeExecution:

    @patch("src.node_executor.time")
    @patch("src.node_executor.logger")
    def test_ai_node_happy_path(self, mock_logger, mock_time):
        """Test AI node execution."""
        mock_time.time.return_value = 1000.0
        llm = _mock_llm()
        result = execute_node(_ai_node(), {"text": "hello"}, llm_client=llm)
        assert result is not None
        assert result.success

    def test_ai_node_calls_correct_model(self):
        """Test model is passed correctly."""
        llm = _mock_llm()
        execute_node(_ai_node(), {"text": "hello"}, llm_client=llm)
        call_args = llm.complete.call_args
        assert call_args[1]["model"] == "claude-sonnet-4-20250514"

    def test_ai_node_renders_template(self):
        """Test prompt template rendering."""
        llm = _mock_llm()
        execute_node(_ai_node(), {"text": "hello world"}, llm_client=llm)
        call_args = llm.complete.call_args
        assert "hello world" in call_args[1]["prompt"]

    def test_ai_node_no_client_raises(self):
        with pytest.raises(NodeExecutionError):
            execute_node(_ai_node(), {"text": "test"}, llm_client=None)

    def test_api_node_happy_path(self):
        http = _mock_http()
        result = execute_node(_api_node(), {"text": "hello"}, http_client=http)
        assert result.success == True
        assert result.output is not None

    def test_api_node_posts_correctly(self):
        http = _mock_http()
        execute_node(_api_node(), {"text": "hello"}, http_client=http)
        http.request.assert_called_once()
        call_args = http.request.call_args
        assert call_args[1]["method"] == "POST"

    def test_api_node_no_client_raises(self):
        with pytest.raises(NodeExecutionError):
            execute_node(_api_node(), {}, http_client=None)

    def test_conditional_true(self):
        node = NodeConfig("c", NodeType.CONDITIONAL, "Check", {"condition_expression": "x > 5"})
        result = execute_node(node, {"x": 10})
        assert result.output["condition_result"] == True

    def test_conditional_false(self):
        node = NodeConfig("c", NodeType.CONDITIONAL, "Check", {"condition_expression": "x > 5"})
        result = execute_node(node, {"x": 1})
        assert result.output["condition_result"] == False

    def test_output_node(self):
        node = NodeConfig("o", NodeType.OUTPUT, "Out", {"destination": "slack"})
        result = execute_node(node, {"message": "hi"})
        assert result is not None

    def test_trigger_node(self):
        node = NodeConfig("t", NodeType.TRIGGER, "Trigger", {"trigger_type": "webhook"})
        result = execute_node(node, {"data": "value"})
        assert result.output["triggered"] == True

    def test_execution_result_dataclass(self):
        """Test NodeExecutionResult fields."""
        r = NodeExecutionResult("id", {"k": "v"}, 100.0, retries=2)
        assert r.node_id == "id"
        assert r.output == {"k": "v"}
        assert r.execution_time_ms == 100.0
        assert r.retries == 2
        assert r.success == True

    @patch("src.node_executor._execute_ai_transform")
    def test_dispatch_routes_ai(self, mock_handler):
        """Test that dispatch calls the right handler."""
        mock_handler.return_value = {"result": "ok"}
        llm = _mock_llm()
        execute_node(_ai_node(), {"text": "test"}, llm_client=llm)
        mock_handler.assert_called_once()

    def test_unknown_node_type_raises(self):
        """Test that an unknown node type raises."""
        node = NodeConfig("x", "unknown_type", "Bad", {})
        with pytest.raises((NodeExecutionError, KeyError, AttributeError)):
            execute_node(node, {})
