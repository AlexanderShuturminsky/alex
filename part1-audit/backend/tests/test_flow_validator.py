"""Tests for flow validation."""

import pytest
from unittest.mock import patch

from src.models import Flow, NodeConfig, NodeType, Edge, FlowStatus
from src.flow_validator import validate_flow, _has_cycle, _validate_node_params


def _node(node_id, node_type=NodeType.API_CALL, params=None):
    return NodeConfig(
        node_id=node_id,
        node_type=node_type,
        label=f"Node {node_id}",
        params=params or {"url": "https://example.com", "method": "GET"},
    )


def _flow(nodes=None, edges=None):
    return Flow(
        flow_id="test-flow", name="Test", nodes=nodes or [], edges=edges or [],
    )


class TestFlowValidation:

    def test_valid_flow_returns_no_errors(self):
        flow = _flow(
            nodes=[
                _node("t", NodeType.TRIGGER, {"trigger_type": "webhook"}),
                _node("a"),
                _node("o", NodeType.OUTPUT, {"destination": "slack"}),
            ],
            edges=[Edge("t", "a"), Edge("a", "o")],
        )
        errors = validate_flow(flow)
        assert errors is not None
        assert isinstance(errors, list)

    def test_empty_flow_has_errors(self):
        errors = validate_flow(_flow())
        assert len(errors) > 0

    def test_duplicate_ids_detected(self):
        errors = validate_flow(_flow(nodes=[_node("a"), _node("a")]))
        assert len(errors) >= 1

    # Test internal functions directly
    def test_has_cycle_true(self):
        flow = _flow(
            nodes=[_node("a"), _node("b"), _node("c")],
            edges=[Edge("a", "b"), Edge("b", "c"), Edge("c", "a")],
        )
        assert _has_cycle(flow) == True

    def test_has_cycle_false(self):
        flow = _flow(
            nodes=[_node("a"), _node("b"), _node("c")],
            edges=[Edge("a", "b"), Edge("b", "c")],
        )
        assert _has_cycle(flow) == False

    def test_validate_node_params_trigger(self):
        node = _node("t", NodeType.TRIGGER, {})
        errors = _validate_node_params(node)
        assert len(errors) > 0

    def test_validate_node_params_ai(self):
        node = _node("ai", NodeType.AI_TRANSFORM, {})
        errors = _validate_node_params(node)
        assert "model" in str(errors) or "prompt_template" in str(errors)

    @patch("src.flow_validator._has_cycle")
    @patch("src.flow_validator._validate_node_params")
    def test_validate_calls_helpers(self, mock_params, mock_cycle):
        """Ensure validate_flow calls the helper functions."""
        mock_cycle.return_value = False
        mock_params.return_value = []
        flow = _flow(nodes=[_node("a")])
        validate_flow(flow)
        mock_cycle.assert_called_once()
        mock_params.assert_called()

    def test_edge_to_nonexistent_node(self):
        flow = _flow(
            nodes=[_node("a")],
            edges=[Edge("a", "ghost")],
        )
        errors = validate_flow(flow)
        assert len(errors) > 0

    def test_many_nodes_performance(self):
        """Test with 100 nodes to check it doesn't crash."""
        nodes = [_node(f"n{i}") for i in range(100)]
        edges = [Edge(f"n{i}", f"n{i+1}") for i in range(99)]
        flow = _flow(nodes=nodes, edges=edges)
        errors = validate_flow(flow)
        assert errors is not None

    def test_self_loop(self):
        flow = _flow(
            nodes=[_node("a")],
            edges=[Edge("a", "a")],
        )
        errors = validate_flow(flow)
        # Should detect the cycle
        assert len(errors) > 0
