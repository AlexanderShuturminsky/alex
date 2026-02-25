"""
Orchestrates end-to-end execution of a Flow.
"""

import time
import logging
import hashlib
from collections import deque
from dataclasses import dataclass, field
from typing import Any, Protocol

from src.models import (
    Flow, FlowRun, NodeConfig, NodeResult, NodeType, RunStatus,
)

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Client protocols
# ---------------------------------------------------------------------------

class LLMClient(Protocol):
    def complete(
        self, model: str, prompt: str, max_tokens: int, temperature: float
    ) -> Any: ...


class HTTPClient(Protocol):
    def request(
        self, method: str, url: str, headers: dict | None = None, json: Any = None
    ) -> Any: ...


# ---------------------------------------------------------------------------
# Built-in simulated clients (deterministic, no external calls)
# ---------------------------------------------------------------------------

@dataclass
class LLMResponse:
    text: str
    usage: int


class SimulatedLLMClient:
    """Deterministic LLM that transforms the prompt into a plausible response."""

    CANNED_RESPONSES = {
        "summarize": "This is a concise summary of the provided content, highlighting the key points and main takeaways.",
        "classify": "Category: high_priority | Confidence: 0.92",
        "draft": "Dear recipient,\n\nThank you for your interest. I'd love to connect and discuss how we can help.\n\nBest regards",
        "enrich": "Company: Acme Corp | Revenue: $5M | Employees: 50 | Industry: SaaS",
        "clean": "Cleaned and normalized data with 3 corrections applied.",
    }

    def complete(self, model: str, prompt: str, max_tokens: int, temperature: float) -> LLMResponse:
        prompt_lower = prompt.lower()
        for keyword, response in self.CANNED_RESPONSES.items():
            if keyword in prompt_lower:
                return LLMResponse(text=response, usage=len(prompt.split()) + len(response.split()))

        digest = hashlib.md5(prompt.encode()).hexdigest()[:8]
        return LLMResponse(
            text=f"Processed input ({digest}): {prompt[:100]}",
            usage=len(prompt.split()) + 12,
        )


@dataclass
class HTTPResponse:
    status_code: int
    text: str
    _json: dict = field(default_factory=dict)

    def json(self) -> dict:
        return self._json


class SimulatedHTTPClient:
    """Deterministic HTTP client that returns canned responses based on the URL/method."""

    def request(self, method: str, url: str, headers: dict | None = None, json: Any = None) -> HTTPResponse:
        if method.upper() == "GET":
            return HTTPResponse(
                status_code=200,
                text=f"<html><body>Simulated GET response from {url}</body></html>",
                _json={"url": url, "records": [{"id": 1, "name": "Sample Record"}, {"id": 2, "name": "Another Record"}]},
            )
        return HTTPResponse(
            status_code=200,
            text="OK",
            _json={"ok": True, "message": f"Simulated {method.upper()} to {url}", "received": json},
        )


# ---------------------------------------------------------------------------
# Flow runner
# ---------------------------------------------------------------------------

class FlowValidationError(Exception):
    def __init__(self, errors: list[str]):
        self.errors = errors
        super().__init__(f"Flow validation failed: {'; '.join(errors)}")


class FlowRunner:
    def __init__(
        self,
        llm_client: LLMClient | None = None,
        http_client: HTTPClient | None = None,
        stop_on_error: bool = True,
    ):
        self.llm_client = llm_client or SimulatedLLMClient()
        self.http_client = http_client or SimulatedHTTPClient()
        self.stop_on_error = stop_on_error
        self._cancelled: set[str] = set()

    def cancel(self, run_id: str) -> None:
        """Mark a run as cancelled. Takes effect between node executions."""
        self._cancelled.add(run_id)

    def run(self, flow_run: FlowRun, flow: Flow) -> FlowRun:
        """
        Execute a flow and populate the FlowRun with results.

        Raises FlowValidationError if the flow is structurally invalid.
        """
        start = time.time()
        flow_run.status = RunStatus.RUNNING

        # Validate
        errors = self._validate(flow)
        if errors:
            flow_run.status = RunStatus.FAILED
            flow_run.error = f"Validation: {'; '.join(errors)}"
            raise FlowValidationError(errors)

        # Topological sort
        execution_order = self._topological_sort(flow)

        # Execute
        node_map = {n.node_id: n for n in flow.nodes}
        node_outputs: dict[str, dict[str, Any]] = {}
        skipped_branches: set[str] = set()

        for node_id in execution_order:
            # Check cancellation
            if flow_run.run_id in self._cancelled:
                flow_run.status = RunStatus.CANCELLED
                flow_run.error = "Run was cancelled"
                self._cancelled.discard(flow_run.run_id)
                break

            node = node_map[node_id]

            if node_id in skipped_branches:
                flow_run.node_results.append(
                    NodeResult(node_id=node_id, output={}, execution_time_ms=0, status="skipped")
                )
                continue

            # Gather inputs
            input_data = dict(flow_run.trigger_data)
            for edge in flow.edges:
                if edge.target_node_id == node_id and edge.source_node_id in node_outputs:
                    input_data.update(node_outputs[edge.source_node_id])

            # Execute node
            node_result = self._execute_node(node, input_data)
            flow_run.node_results.append(node_result)

            if node_result.status == "success":
                node_outputs[node_id] = node_result.output

                if node.node_type == NodeType.CONDITIONAL:
                    skip_branch = node_result.output.get("branch")
                    if skip_branch:
                        targets = self._get_branch_targets(flow, node_id, skip_branch)
                        skipped_branches.update(targets)
            else:
                if self.stop_on_error:
                    flow_run.status = RunStatus.FAILED
                    flow_run.error = f"Node '{node_id}': {node_result.error}"
                    break

        if flow_run.status == RunStatus.RUNNING:
            has_failures = any(nr.status == "failed" for nr in flow_run.node_results)
            flow_run.status = RunStatus.COMPLETED if not has_failures else RunStatus.FAILED
            if has_failures:
                flow_run.status = RunStatus.FAILED

        from datetime import datetime
        flow_run.total_time_ms = (time.time() - start) * 1000
        flow_run.completed_at = datetime.utcnow()
        return flow_run

    # --- Validation ---

    def _validate(self, flow: Flow) -> list[str]:
        errors = []
        if not flow.nodes:
            errors.append("Flow must contain at least one node")
            return errors

        node_ids = {n.node_id for n in flow.nodes}
        if len(node_ids) != len(flow.nodes):
            errors.append("Flow contains duplicate node IDs")

        for edge in flow.edges:
            if edge.source_node_id not in node_ids:
                errors.append(f"Edge references unknown source: {edge.source_node_id}")
            if edge.target_node_id not in node_ids:
                errors.append(f"Edge references unknown target: {edge.target_node_id}")

        if self._has_cycle(flow):
            errors.append("Flow contains a cycle")

        return errors

    def _has_cycle(self, flow: Flow) -> bool:
        adj: dict[str, list[str]] = {n.node_id: [] for n in flow.nodes}
        in_degree: dict[str, int] = {n.node_id: 0 for n in flow.nodes}
        for edge in flow.edges:
            if edge.source_node_id in adj:
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

    # --- Topological sort ---

    def _topological_sort(self, flow: Flow) -> list[str]:
        adj: dict[str, list[str]] = {n.node_id: [] for n in flow.nodes}
        in_degree: dict[str, int] = {n.node_id: 0 for n in flow.nodes}
        for edge in flow.edges:
            adj[edge.source_node_id].append(edge.target_node_id)
            in_degree[edge.target_node_id] += 1

        queue = deque(nid for nid, deg in in_degree.items() if deg == 0)
        order = []
        while queue:
            node = queue.popleft()
            order.append(node)
            for neighbor in adj[node]:
                in_degree[neighbor] -= 1
                if in_degree[neighbor] == 0:
                    queue.append(neighbor)
        return order

    # --- Node execution ---

    def _execute_node(self, node: NodeConfig, input_data: dict[str, Any]) -> NodeResult:
        start = time.time()
        try:
            output = self._dispatch(node, input_data)
            elapsed = (time.time() - start) * 1000
            return NodeResult(node_id=node.node_id, output=output, execution_time_ms=elapsed)
        except Exception as e:
            elapsed = (time.time() - start) * 1000
            logger.error(f"Node '{node.node_id}' failed: {e}")
            return NodeResult(
                node_id=node.node_id, output={}, execution_time_ms=elapsed,
                status="failed", error=str(e),
            )

    def _dispatch(self, node: NodeConfig, input_data: dict[str, Any]) -> dict[str, Any]:
        if node.node_type == NodeType.TRIGGER:
            return {"triggered": True, **input_data}

        elif node.node_type == NodeType.AI_TRANSFORM:
            template = node.params.get("prompt_template", "")
            try:
                rendered = template.format(**input_data)
            except KeyError:
                rendered = template
            response = self.llm_client.complete(
                model=node.params.get("model", "claude-sonnet-4-20250514"),
                prompt=rendered,
                max_tokens=node.params.get("max_tokens", 1024),
                temperature=node.params.get("temperature", 0.0),
            )
            return {"result": response.text, "model": node.params.get("model"), "tokens_used": response.usage}

        elif node.node_type == NodeType.API_CALL:
            service = node.params.get("service", "unknown")
            url = node.params.get("url", f"https://{service}.example.com/api")
            try:
                url = url.format(**input_data)
            except KeyError:
                pass
            method = node.params.get("method", "POST").upper()
            body = node.params.get("body")
            if body and isinstance(body, str):
                try:
                    body = body.format(**input_data)
                except KeyError:
                    pass
            resp = self.http_client.request(
                method=method, url=url,
                headers=node.params.get("headers"),
                json=body if method in ("POST", "PUT", "PATCH") else None,
            )
            if resp.status_code >= 400:
                raise RuntimeError(f"API call failed: {resp.status_code}")
            return {"status_code": resp.status_code, "service": service, "body": resp.json()}

        elif node.node_type == NodeType.CONDITIONAL:
            condition = node.params.get("condition_expression")
            if condition:
                result = eval(condition, {"__builtins__": {}}, input_data)
            else:
                result = True
            return {"condition_result": bool(result), "branch": "false" if result else "true"}

        elif node.node_type == NodeType.OUTPUT:
            destination = node.params.get("destination", "default")
            return {"destination": destination, "payload": input_data, "delivered": True}

        elif node.node_type == NodeType.WEB_SCRAPER:
            target = node.params.get("target_url", f"https://{node.label.lower().replace(' ', '-')}.example.com")
            try:
                target = target.format(**input_data)
            except KeyError:
                pass
            resp = self.http_client.request(method="GET", url=target, headers={})
            if resp.status_code >= 400:
                raise RuntimeError(f"Scrape failed: {resp.status_code}")
            return {"raw_html": resp.text, "url": target, "records": resp.json().get("records", [])}

        elif node.node_type == NodeType.DATA_TRANSFORM:
            expr = node.params.get("transform_expression")
            if expr:
                result = eval(expr, {"__builtins__": {}}, input_data)
                return {"transformed": result}
            return {"transformed": input_data, "rows_processed": len(input_data)}

        else:
            raise RuntimeError(f"Unknown node type: {node.node_type}")

    # --- Branch helpers ---

    def _get_branch_targets(self, flow: Flow, cond_id: str, branch: str) -> set[str]:
        targets = set()
        for edge in flow.edges:
            if edge.source_node_id == cond_id and edge.source_output == branch:
                targets.add(edge.target_node_id)
                targets.update(self._get_all_downstream(flow, edge.target_node_id))
        return targets

    def _get_all_downstream(self, flow: Flow, node_id: str) -> set[str]:
        downstream = set()
        queue = deque([node_id])
        while queue:
            current = queue.popleft()
            for edge in flow.edges:
                if edge.source_node_id == current and edge.target_node_id not in downstream:
                    downstream.add(edge.target_node_id)
                    queue.append(edge.target_node_id)
        return downstream
