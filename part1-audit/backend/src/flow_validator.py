"""
Validates flow graph structure before execution.
"""

from collections import deque

from src.models import Flow, NodeType, Edge, NodeConfig


class FlowValidationError(Exception):
    def __init__(self, errors: list[str]):
        self.errors = errors
        super().__init__(f"Flow validation failed: {'; '.join(errors)}")


def validate_flow(flow: Flow) -> list[str]:
    """
    Validates a flow and returns a list of error strings.
    Returns an empty list if the flow is valid.
    """
    errors = []

    if not flow.nodes:
        errors.append("Flow must contain at least one node")
        return errors

    node_ids = {n.node_id for n in flow.nodes}

    if len(node_ids) != len(flow.nodes):
        seen = set()
        for n in flow.nodes:
            if n.node_id in seen:
                errors.append(f"Duplicate node ID: {n.node_id}")
            seen.add(n.node_id)

    for edge in flow.edges:
        if edge.source_node_id not in node_ids:
            errors.append(
                f"Edge references non-existent source node: {edge.source_node_id}"
            )
        if edge.target_node_id not in node_ids:
            errors.append(
                f"Edge references non-existent target node: {edge.target_node_id}"
            )

    if _has_cycle(flow):
        errors.append("Flow contains a cycle")

    trigger_ids = {n.node_id for n in flow.nodes if n.node_type == NodeType.TRIGGER}
    for edge in flow.edges:
        if edge.target_node_id in trigger_ids:
            errors.append(
                f"Trigger node '{edge.target_node_id}' cannot have incoming edges"
            )

    for node in flow.nodes:
        param_errors = _validate_node_params(node)
        errors.extend(param_errors)

    return errors


def _has_cycle(flow: Flow) -> bool:
    adj: dict[str, list[str]] = {n.node_id: [] for n in flow.nodes}
    in_degree: dict[str, int] = {n.node_id: 0 for n in flow.nodes}
    for edge in flow.edges:
        if edge.source_node_id in adj and edge.target_node_id in adj:
            adj[edge.source_node_id].append(edge.target_node_id)
            in_degree[edge.target_node_id] = in_degree.get(edge.target_node_id, 0) + 1

    queue = deque(nid for nid, deg in in_degree.items() if deg == 0)
    visited = 0
    while queue:
        node = queue.popleft()
        visited += 1
        for neighbor in adj[node]:
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0:
                queue.append(neighbor)

    return visited != len(flow.nodes)


def _validate_node_params(node: NodeConfig) -> list[str]:
    errors = []
    required_params: dict[NodeType, list[str]] = {
        NodeType.AI_TRANSFORM: ["model", "prompt_template"],
        NodeType.API_CALL: ["url", "method"],
        NodeType.CONDITIONAL: ["condition_expression"],
        NodeType.OUTPUT: ["destination"],
        NodeType.TRIGGER: ["trigger_type"],
        NodeType.WEB_SCRAPER: ["target_url", "selectors"],
        NodeType.DATA_TRANSFORM: ["transform_expression"],
    }

    required = required_params.get(node.node_type, [])
    for param in required:
        if param not in node.params:
            errors.append(
                f"Node '{node.node_id}' ({node.node_type.value}) missing "
                f"required param: {param}"
            )

    # Validate AI model is in allowed list
    if node.node_type == NodeType.AI_TRANSFORM:
        model = node.params.get("model", "")
        allowed_models = {
            "claude-sonnet-4-20250514", "claude-haiku-4-5-20251001",
            "gpt-4o", "gpt-4o-mini",
        }
        if model and model not in allowed_models:
            errors.append(f"Node '{node.node_id}': unsupported model '{model}'")

    # Validate HTTP method
    if node.node_type == NodeType.API_CALL:
        method = node.params.get("method", "").upper()
        if method and method not in {"GET", "POST", "PUT", "PATCH", "DELETE"}:
            errors.append(f"Node '{node.node_id}': invalid HTTP method '{method}'")

    return errors
