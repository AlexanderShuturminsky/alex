"""
Flask API for Gumloop's template gallery and flow execution.
"""

import uuid
from flask import Flask, request, jsonify, g

from src.models import (
    FlowTemplate, FlowRun, Flow, NodeConfig, NodeType, Edge,
    TemplateCategory, RunStatus,
)
from src.template_service import (
    TemplateService, TemplateNotFoundError,
    TemplatePermissionError, TemplateValidationError, RateLimitError,
)
from src.flow_runner import FlowRunner, FlowValidationError


DEV_USER = "user-dev"


def _seed(ts: TemplateService) -> None:
    """Populate sample templates so the gallery isn't empty."""
    templates = [
        FlowTemplate(
            template_id="tmpl-1",
            name="Email Outreach Automator",
            description="Draft and send personalized cold emails using AI based on lead data.",
            category=TemplateCategory.MARKETING,
            nodes=[
                NodeConfig("trigger-1", NodeType.TRIGGER, "New Lead", {"source": "webhook"}),
                NodeConfig("ai-1", NodeType.AI_TRANSFORM, "Draft Email",
                           {"model": "claude-sonnet-4-20250514", "prompt_template": "Write outreach email for: {lead}"}),
                NodeConfig("output-1", NodeType.OUTPUT, "Send Email", {"destination": "gmail"}),
            ],
            edges=[Edge("trigger-1", "ai-1"), Edge("ai-1", "output-1")],
            author_id="user-1",
            tags=["email", "outreach", "ai"],
            use_count=1834,
        ),
        FlowTemplate(
            template_id="tmpl-2",
            name="Support Ticket Router",
            description="Classify incoming support tickets with AI and route to the right team.",
            category=TemplateCategory.SUPPORT,
            nodes=[
                NodeConfig("trigger-1", NodeType.TRIGGER, "New Ticket", {"source": "zendesk"}),
                NodeConfig("ai-1", NodeType.AI_TRANSFORM, "Classify Intent",
                           {"model": "claude-sonnet-4-20250514", "prompt_template": "Classify this ticket: {body}"}),
                NodeConfig("cond-1", NodeType.CONDITIONAL, "Route", {"rules": "priority-based"}),
                NodeConfig("output-1", NodeType.OUTPUT, "Assign Agent", {"destination": "slack"}),
            ],
            edges=[Edge("trigger-1", "ai-1"), Edge("ai-1", "cond-1"), Edge("cond-1", "output-1")],
            author_id=DEV_USER,
            tags=["support", "routing", "classification"],
            use_count=567,
        ),
        FlowTemplate(
            template_id="tmpl-3",
            name="Lead Scraper Pipeline",
            description="Scrape leads from websites, enrich with AI, and push to CRM.",
            category=TemplateCategory.SALES,
            nodes=[
                NodeConfig("trigger-1", NodeType.TRIGGER, "Schedule", {"cron": "0 9 * * 1"}),
                NodeConfig("scrape-1", NodeType.WEB_SCRAPER, "Scrape LinkedIn"),
                NodeConfig("ai-1", NodeType.AI_TRANSFORM, "Enrich Data",
                           {"model": "claude-sonnet-4-20250514", "prompt_template": "Enrich lead: {raw}"}),
                NodeConfig("output-1", NodeType.API_CALL, "Push to CRM", {"service": "hubspot"}),
            ],
            edges=[Edge("trigger-1", "scrape-1"), Edge("scrape-1", "ai-1"), Edge("ai-1", "output-1")],
            author_id="user-2",
            tags=["leads", "scraping", "crm"],
            use_count=921,
        ),
        FlowTemplate(
            template_id="tmpl-4",
            name="CSV Data Transformer",
            description="Upload a CSV, clean columns with AI, and export to Google Sheets.",
            category=TemplateCategory.DATA_PROCESSING,
            nodes=[
                NodeConfig("trigger-1", NodeType.TRIGGER, "File Upload"),
                NodeConfig("transform-1", NodeType.DATA_TRANSFORM, "Parse CSV"),
                NodeConfig("ai-1", NodeType.AI_TRANSFORM, "Clean Data",
                           {"model": "claude-sonnet-4-20250514", "prompt_template": "Clean: {row}"}),
                NodeConfig("output-1", NodeType.API_CALL, "Export to Sheets", {"service": "google-sheets"}),
            ],
            edges=[Edge("trigger-1", "transform-1"), Edge("transform-1", "ai-1"), Edge("ai-1", "output-1")],
            author_id="user-3",
            tags=["csv", "data", "etl"],
            use_count=412,
        ),
    ]
    for t in templates:
        ts._store[t.template_id] = t


def create_app(
    template_service: TemplateService | None = None,
    flow_runner: FlowRunner | None = None,
    seed: bool = True,
) -> Flask:
    app = Flask(__name__)

    ts = template_service or TemplateService()
    runner = flow_runner or FlowRunner()

    if seed and not ts._store:
        _seed(ts)

    # In-memory stores for flows and runs
    flows_store: dict[str, Flow] = {}
    runs_store: dict[str, FlowRun] = {}

    # --- Middleware ---

    @app.before_request
    def extract_user():
        """Extract user ID from header; defaults to DEV_USER for local dev."""
        g.user_id = request.headers.get("X-User-Id", DEV_USER)

    # --- Health ---

    @app.route("/api/v1/health")
    def health():
        return jsonify({"status": "ok"})

    # --- Templates ---

    @app.route("/api/v1/templates", methods=["GET"])
    def list_templates():
        category = request.args.get("category")
        search = request.args.get("search")
        page = int(request.args.get("page", 1))
        page_size = int(request.args.get("page_size", 20))

        cat_enum = None
        if category:
            try:
                cat_enum = TemplateCategory(category)
            except ValueError:
                return jsonify({"error": f"Invalid category: {category}"}), 400

        templates, total = ts.list_templates(
            category=cat_enum, search_query=search, page=page, page_size=page_size,
        )

        return jsonify({
            "items": [_template_to_dict(t) for t in templates],
            "total": total,
            "page": page,
            "pageSize": page_size,
        })

    @app.route("/api/v1/templates/<template_id>", methods=["GET"])
    def get_template(template_id):
        try:
            template = ts.get_template(template_id, g.user_id)
            return jsonify(_template_to_dict(template))
        except TemplateNotFoundError:
            return jsonify({"error": "Template not found"}), 404
        except TemplatePermissionError:
            return jsonify({"error": "Access denied"}), 403

    @app.route("/api/v1/templates", methods=["POST"])
    def create_template():
        data = request.json
        if not data:
            return jsonify({"error": "Request body required"}), 400

        try:
            nodes = [
                NodeConfig(
                    node_id=n["nodeId"],
                    node_type=NodeType(n["nodeType"]),
                    label=n.get("label", ""),
                    params=n.get("params", {}),
                    position=n.get("position", {"x": 0, "y": 0}),
                )
                for n in data.get("nodes", [])
            ]
            edges = [
                Edge(
                    source_node_id=e["sourceNodeId"],
                    target_node_id=e["targetNodeId"],
                    source_output=e.get("sourceOutput", "default"),
                    target_input=e.get("targetInput", "default"),
                )
                for e in data.get("edges", [])
            ]
        except (KeyError, ValueError) as e:
            return jsonify({"error": f"Invalid node/edge data: {e}"}), 400

        template = FlowTemplate(
            template_id=str(uuid.uuid4()),
            name=data.get("name", ""),
            description=data.get("description", ""),
            category=TemplateCategory(data.get("category", "custom")),
            nodes=nodes,
            edges=edges,
            tags=data.get("tags", []),
            is_public=data.get("isPublic", True),
        )

        try:
            created = ts.create_template(template, g.user_id)
            return jsonify(_template_to_dict(created)), 201
        except TemplateValidationError as e:
            return jsonify({"error": e.errors}), 400

    @app.route("/api/v1/templates/<template_id>", methods=["DELETE"])
    def delete_template(template_id):
        try:
            ts.delete_template(template_id, g.user_id)
            return "", 204
        except TemplateNotFoundError:
            return jsonify({"error": "Template not found"}), 404
        except TemplatePermissionError:
            return jsonify({"error": "Access denied"}), 403

    @app.route("/api/v1/templates/<template_id>/clone", methods=["POST"])
    def clone_template(template_id):
        data = request.json or {}
        flow_name = data.get("flowName")

        try:
            flow = ts.clone_template(template_id, g.user_id, flow_name)
            flows_store[flow.flow_id] = flow
            return jsonify(_flow_to_dict(flow)), 201
        except TemplateNotFoundError:
            return jsonify({"error": "Template not found"}), 404
        except TemplatePermissionError:
            return jsonify({"error": "Access denied"}), 403
        except RateLimitError:
            return jsonify({"error": "Rate limit exceeded"}), 429

    # --- Flow Execution ---

    @app.route("/api/v1/flows/<flow_id>/run", methods=["POST"])
    def run_flow(flow_id):
        flow = flows_store.get(flow_id)
        if not flow:
            return jsonify({"error": "Flow not found"}), 404

        if flow.owner_id != g.user_id:
            return jsonify({"error": "Access denied"}), 403

        data = request.json or {}
        trigger_data = data.get("triggerData", {})

        flow_run = FlowRun(
            run_id=str(uuid.uuid4()),
            flow_id=flow_id,
            owner_id=g.user_id,
            trigger_data=trigger_data,
        )

        try:
            result = runner.run(flow_run, flow)
            runs_store[result.run_id] = result
            return jsonify(_run_to_dict(result)), 200
        except FlowValidationError as e:
            flow_run.status = RunStatus.FAILED
            flow_run.error = str(e)
            runs_store[flow_run.run_id] = flow_run
            return jsonify(_run_to_dict(flow_run)), 400

    @app.route("/api/v1/runs/<run_id>", methods=["GET"])
    def get_run(run_id):
        run = runs_store.get(run_id)
        if not run:
            return jsonify({"error": "Run not found"}), 404
        if run.owner_id != g.user_id:
            return jsonify({"error": "Access denied"}), 403
        return jsonify(_run_to_dict(run))

    @app.route("/api/v1/runs/<run_id>/cancel", methods=["POST"])
    def cancel_run(run_id):
        run = runs_store.get(run_id)
        if not run:
            return jsonify({"error": "Run not found"}), 404
        if run.owner_id != g.user_id:
            return jsonify({"error": "Access denied"}), 403
        if run.status not in (RunStatus.PENDING, RunStatus.RUNNING):
            return jsonify({"error": "Run is not active"}), 409
        runner.cancel(run_id)
        run.status = RunStatus.CANCELLED
        return jsonify(_run_to_dict(run))

    # --- Serialization helpers ---

    def _template_to_dict(t: FlowTemplate) -> dict:
        return {
            "templateId": t.template_id,
            "name": t.name,
            "description": t.description,
            "category": t.category.value,
            "nodes": [_node_to_dict(n) for n in t.nodes],
            "edges": [_edge_to_dict(e) for e in t.edges],
            "authorId": t.author_id,
            "isPublic": t.is_public,
            "useCount": t.use_count,
            "tags": t.tags,
            "createdAt": t.created_at.isoformat(),
        }

    def _flow_to_dict(f: Flow) -> dict:
        return {
            "flowId": f.flow_id,
            "name": f.name,
            "nodes": [_node_to_dict(n) for n in f.nodes],
            "edges": [_edge_to_dict(e) for e in f.edges],
            "status": f.status.value,
            "ownerId": f.owner_id,
        }

    def _node_to_dict(n: NodeConfig) -> dict:
        return {
            "nodeId": n.node_id,
            "nodeType": n.node_type.value,
            "label": n.label,
            "params": n.params,
            "position": n.position,
        }

    def _edge_to_dict(e: Edge) -> dict:
        return {
            "sourceNodeId": e.source_node_id,
            "targetNodeId": e.target_node_id,
            "sourceOutput": e.source_output,
            "targetInput": e.target_input,
        }

    def _run_to_dict(r: FlowRun) -> dict:
        return {
            "runId": r.run_id,
            "flowId": r.flow_id,
            "ownerId": r.owner_id,
            "status": r.status.value,
            "triggerData": r.trigger_data,
            "nodeResults": [
                {
                    "nodeId": nr.node_id,
                    "output": nr.output,
                    "executionTimeMs": nr.execution_time_ms,
                    "status": nr.status,
                    "error": nr.error,
                }
                for nr in r.node_results
            ],
            "totalTimeMs": r.total_time_ms,
            "error": r.error,
            "createdAt": r.created_at.isoformat(),
            "completedAt": r.completed_at.isoformat() if r.completed_at else None,
        }

    return app
