"""
Data models for Gumloop's flow execution engine.
"""

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any
import uuid


class NodeType(Enum):
    TRIGGER = "trigger"
    AI_TRANSFORM = "ai_transform"
    API_CALL = "api_call"
    CONDITIONAL = "conditional"
    OUTPUT = "output"
    WEB_SCRAPER = "web_scraper"
    DATA_TRANSFORM = "data_transform"


class FlowStatus(Enum):
    DRAFT = "draft"
    ACTIVE = "active"
    PAUSED = "paused"
    ERROR = "error"


class TemplateCategory(Enum):
    MARKETING = "marketing"
    SALES = "sales"
    SUPPORT = "support"
    DATA_PROCESSING = "data_processing"
    CUSTOM = "custom"


@dataclass
class NodeConfig:
    node_id: str
    node_type: NodeType
    label: str
    params: dict[str, Any] = field(default_factory=dict)
    position: dict[str, float] = field(default_factory=lambda: {"x": 0, "y": 0})


@dataclass
class Edge:
    source_node_id: str
    target_node_id: str
    source_output: str = "default"
    target_input: str = "default"


@dataclass
class Flow:
    flow_id: str
    name: str
    nodes: list[NodeConfig] = field(default_factory=list)
    edges: list[Edge] = field(default_factory=list)
    status: FlowStatus = FlowStatus.DRAFT
    owner_id: str | None = None
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)


@dataclass
class FlowTemplate:
    template_id: str
    name: str
    description: str
    category: TemplateCategory
    nodes: list[NodeConfig] = field(default_factory=list)
    edges: list[Edge] = field(default_factory=list)
    author_id: str | None = None
    is_public: bool = True
    use_count: int = 0
    tags: list[str] = field(default_factory=list)
    created_at: datetime = field(default_factory=datetime.utcnow)

    def clone_to_flow(self, owner_id: str, name: str | None = None) -> Flow:
        """Create a new Flow from this template."""
        new_nodes = []
        id_mapping: dict[str, str] = {}

        for node in self.nodes:
            new_id = str(uuid.uuid4())[:8]
            id_mapping[node.node_id] = new_id
            new_nodes.append(
                NodeConfig(
                    node_id=new_id,
                    node_type=node.node_type,
                    label=node.label,
                    params=dict(node.params),
                    position=dict(node.position),
                )
            )

        new_edges = []
        for edge in self.edges:
            new_edges.append(
                Edge(
                    source_node_id=id_mapping.get(edge.source_node_id, edge.source_node_id),
                    target_node_id=id_mapping.get(edge.target_node_id, edge.target_node_id),
                    source_output=edge.source_output,
                    target_input=edge.target_input,
                )
            )

        return Flow(
            flow_id=str(uuid.uuid4()),
            name=name or f"Copy of {self.name}",
            nodes=new_nodes,
            edges=new_edges,
            owner_id=owner_id,
        )
