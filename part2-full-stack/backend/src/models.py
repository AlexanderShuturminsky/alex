"""Data models for Gumloop's flow engine."""

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


class RunStatus(Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


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
class NodeResult:
    node_id: str
    output: dict[str, Any]
    execution_time_ms: float
    status: str = "success"  # success, failed, skipped, cancelled
    error: str | None = None


@dataclass
class FlowRun:
    run_id: str
    flow_id: str
    owner_id: str
    status: RunStatus = RunStatus.PENDING
    trigger_data: dict[str, Any] = field(default_factory=dict)
    node_results: list[NodeResult] = field(default_factory=list)
    total_time_ms: float = 0.0
    error: str | None = None
    created_at: datetime = field(default_factory=datetime.utcnow)
    completed_at: datetime | None = None

    def to_dict(self) -> dict:
        return {
            "run_id": self.run_id,
            "flow_id": self.flow_id,
            "owner_id": self.owner_id,
            "status": self.status.value,
            "trigger_data": self.trigger_data,
            "node_results": [
                {
                    "node_id": nr.node_id,
                    "output": nr.output,
                    "execution_time_ms": nr.execution_time_ms,
                    "status": nr.status,
                    "error": nr.error,
                }
                for nr in self.node_results
            ],
            "total_time_ms": self.total_time_ms,
            "error": self.error,
            "created_at": self.created_at.isoformat(),
            "completed_at": self.completed_at.isoformat() if self.completed_at else None,
        }


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
        new_edges = [
            Edge(
                source_node_id=id_mapping.get(e.source_node_id, e.source_node_id),
                target_node_id=id_mapping.get(e.target_node_id, e.target_node_id),
                source_output=e.source_output,
                target_input=e.target_input,
            )
            for e in self.edges
        ]
        return Flow(
            flow_id=str(uuid.uuid4()),
            name=name or f"Copy of {self.name}",
            nodes=new_nodes,
            edges=new_edges,
            owner_id=owner_id,
        )
