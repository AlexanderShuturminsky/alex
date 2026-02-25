"""
Minimal Flask dev server to browse the Template Gallery.
Run with: flask --app app run --port 5000
"""

from flask import Flask, jsonify, request
from src.models import FlowTemplate, NodeConfig, Edge, TemplateCategory, NodeType
from src.template_service import TemplateService, TemplateNotFoundError, TemplatePermissionError, RateLimitError

app = Flask(__name__)
service = TemplateService()

DEV_USER = "user-dev"

def _seed():
    templates = [
        FlowTemplate(
            template_id="tmpl-1",
            name="Email Outreach Automator",
            description="Automatically draft and send personalized cold emails using AI based on lead data.",
            category=TemplateCategory.MARKETING,
            nodes=[
                NodeConfig("n1", NodeType.TRIGGER, "New Lead", {"source": "webhook"}),
                NodeConfig("n2", NodeType.AI_TRANSFORM, "Draft Email", {"model": "gpt-4", "prompt": "Write outreach email"}),
                NodeConfig("n3", NodeType.API_CALL, "Send Email", {"service": "gmail"}),
            ],
            edges=[Edge("n1", "n2"), Edge("n2", "n3")],
            author_id="user-1",
            tags=["email", "outreach", "ai", "cold-email"],
            use_count=1834,
        ),
        FlowTemplate(
            template_id="tmpl-2",
            name="Lead Scraper Pipeline",
            description="Scrape leads from LinkedIn and company websites, enrich with AI, and push to CRM.",
            category=TemplateCategory.SALES,
            nodes=[
                NodeConfig("n1", NodeType.TRIGGER, "Schedule", {"cron": "0 9 * * 1"}),
                NodeConfig("n2", NodeType.WEB_SCRAPER, "Scrape LinkedIn"),
                NodeConfig("n3", NodeType.AI_TRANSFORM, "Enrich Data"),
                NodeConfig("n4", NodeType.API_CALL, "Push to CRM", {"service": "hubspot"}),
            ],
            edges=[Edge("n1", "n2"), Edge("n2", "n3"), Edge("n3", "n4")],
            author_id="user-2",
            tags=["leads", "scraping", "linkedin", "crm"],
            use_count=921,
        ),
        FlowTemplate(
            template_id="tmpl-3",
            name="Support Ticket Router",
            description="Classify incoming support tickets with AI and route to the right team automatically.",
            category=TemplateCategory.SUPPORT,
            nodes=[
                NodeConfig("n1", NodeType.TRIGGER, "New Ticket"),
                NodeConfig("n2", NodeType.AI_TRANSFORM, "Classify Intent"),
                NodeConfig("n3", NodeType.CONDITIONAL, "Route", {"rules": "priority-based"}),
                NodeConfig("n4", NodeType.OUTPUT, "Assign Agent"),
            ],
            edges=[Edge("n1", "n2"), Edge("n2", "n3"), Edge("n3", "n4")],
            author_id=DEV_USER,
            tags=["support", "routing", "classification"],
            use_count=567,
        ),
        FlowTemplate(
            template_id="tmpl-4",
            name="CSV Data Transformer",
            description="Upload a CSV, clean and transform columns with AI, then export to Google Sheets.",
            category=TemplateCategory.DATA_PROCESSING,
            nodes=[
                NodeConfig("n1", NodeType.TRIGGER, "File Upload"),
                NodeConfig("n2", NodeType.DATA_TRANSFORM, "Parse CSV"),
                NodeConfig("n3", NodeType.AI_TRANSFORM, "Clean Data"),
                NodeConfig("n4", NodeType.API_CALL, "Export to Sheets", {"service": "google-sheets"}),
            ],
            edges=[Edge("n1", "n2"), Edge("n2", "n3"), Edge("n3", "n4")],
            author_id="user-3",
            tags=["csv", "data", "etl", "google-sheets"],
            use_count=412,
        ),
        FlowTemplate(
            template_id="tmpl-5",
            name="Social Media Monitor",
            description="Track brand mentions across Twitter and Reddit, summarize with AI, and alert on Slack.",
            category=TemplateCategory.MARKETING,
            nodes=[
                NodeConfig("n1", NodeType.TRIGGER, "Cron (15min)"),
                NodeConfig("n2", NodeType.WEB_SCRAPER, "Scrape Mentions"),
                NodeConfig("n3", NodeType.AI_TRANSFORM, "Summarize"),
                NodeConfig("n4", NodeType.CONDITIONAL, "Sentiment Check"),
                NodeConfig("n5", NodeType.API_CALL, "Slack Alert", {"service": "slack"}),
            ],
            edges=[Edge("n1", "n2"), Edge("n2", "n3"), Edge("n3", "n4"), Edge("n4", "n5")],
            author_id="user-1",
            tags=["social-media", "monitoring", "slack"],
            use_count=289,
        ),
        FlowTemplate(
            template_id="tmpl-6",
            name="Invoice Processor",
            description="Extract data from PDF invoices using AI and create entries in your accounting system.",
            category=TemplateCategory.DATA_PROCESSING,
            nodes=[
                NodeConfig("n1", NodeType.TRIGGER, "Email Attachment"),
                NodeConfig("n2", NodeType.AI_TRANSFORM, "Extract Fields"),
                NodeConfig("n3", NodeType.API_CALL, "Create Entry", {"service": "quickbooks"}),
            ],
            edges=[Edge("n1", "n2"), Edge("n2", "n3")],
            author_id=DEV_USER,
            tags=["invoices", "pdf", "accounting"],
            use_count=198,
        ),
    ]
    for t in templates:
        service._store[t.template_id] = t


def _template_to_dict(t: FlowTemplate) -> dict:
    return {
        "templateId": t.template_id,
        "name": t.name,
        "description": t.description,
        "category": t.category.value,
        "nodes": [
            {"nodeId": n.node_id, "nodeType": n.node_type.value, "label": n.label, "params": n.params, "position": n.position}
            for n in t.nodes
        ],
        "edges": [
            {"sourceNodeId": e.source_node_id, "targetNodeId": e.target_node_id, "sourceOutput": e.source_output, "targetInput": e.target_input}
            for e in t.edges
        ],
        "authorId": t.author_id,
        "isPublic": t.is_public,
        "useCount": t.use_count,
        "tags": t.tags,
        "createdAt": t.created_at.isoformat() + "Z",
    }


@app.route("/api/v1/templates")
def list_templates():
    category_str = request.args.get("category")
    category = TemplateCategory(category_str) if category_str else None
    search = request.args.get("search")
    page = int(request.args.get("page", 1))
    page_size = int(request.args.get("page_size", 12))

    templates, total = service.list_templates(
        category=category, search_query=search, page=page, page_size=page_size
    )
    return jsonify({
        "items": [_template_to_dict(t) for t in templates],
        "total": total,
        "page": page,
        "pageSize": page_size,
    })


@app.route("/api/v1/templates/<template_id>/clone", methods=["POST"])
def clone_template(template_id):
    data = request.get_json(silent=True) or {}
    flow_name = data.get("flowName")
    try:
        flow = service.clone_template(template_id, DEV_USER, flow_name)
        return jsonify({
            "flowId": flow.flow_id,
            "name": flow.name,
            "status": flow.status.value,
        })
    except TemplateNotFoundError as e:
        return jsonify({"error": str(e)}), 404
    except RateLimitError as e:
        return jsonify({"error": str(e)}), 429


@app.route("/api/v1/templates/<template_id>", methods=["DELETE"])
def delete_template_route(template_id):
    try:
        service.delete_template(template_id, DEV_USER)
        return "", 204
    except TemplateNotFoundError as e:
        return jsonify({"error": str(e)}), 404
    except TemplatePermissionError as e:
        return jsonify({"error": str(e)}), 403


_seed()
