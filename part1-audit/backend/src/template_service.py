"""
Service layer for managing Flow Templates.
Handles CRUD, search, cloning, and usage tracking.
"""

import logging
import re
from datetime import datetime
from typing import Any

from src.models import FlowTemplate, Flow, TemplateCategory, NodeType

logger = logging.getLogger(__name__)


class TemplateNotFoundError(Exception):
    pass


class TemplatePermissionError(Exception):
    pass


class TemplateValidationError(Exception):
    def __init__(self, errors: list[str]):
        self.errors = errors
        super().__init__(f"Validation failed: {'; '.join(errors)}")


class RateLimitError(Exception):
    def __init__(self, user_id: str, limit: int):
        self.user_id = user_id
        self.limit = limit
        super().__init__(f"User '{user_id}' exceeded rate limit of {limit} clones/hour")


class TemplateService:
    """
    Manages template lifecycle. In production this talks to a database;
    for simplicity this uses an in-memory store.
    """

    MAX_CLONES_PER_HOUR = 10
    MAX_TEMPLATES_PER_USER = 50
    ALLOWED_NAME_PATTERN = re.compile(r"^[\w\s\-\.]{1,100}$")

    def __init__(self, store: dict[str, FlowTemplate] | None = None):
        self._store: dict[str, FlowTemplate] = store or {}
        self._clone_log: dict[str, list[datetime]] = {}  # user_id → timestamps

    def create_template(
        self,
        template: FlowTemplate,
        user_id: str,
    ) -> FlowTemplate:
        """Create a new template. Validates structure and permissions."""
        errors = self._validate_template(template)
        if errors:
            raise TemplateValidationError(errors)

        user_count = sum(
            1 for t in self._store.values() if t.author_id == user_id
        )
        if user_count >= self.MAX_TEMPLATES_PER_USER:
            raise TemplateValidationError(
                [f"User has reached maximum of {self.MAX_TEMPLATES_PER_USER} templates"]
            )

        template.author_id = user_id
        template.created_at = datetime.utcnow()
        self._store[template.template_id] = template
        logger.info(f"Template '{template.template_id}' created by '{user_id}'")
        return template

    def get_template(self, template_id: str, user_id: str | None = None) -> FlowTemplate:
        """Retrieve a template by ID. Checks visibility permissions."""
        template = self._store.get(template_id)
        if not template:
            raise TemplateNotFoundError(f"Template '{template_id}' not found")

        if not template.is_public and template.author_id != user_id:
            raise TemplatePermissionError(
                f"User '{user_id}' cannot access private template '{template_id}'"
            )

        return template

    def list_templates(
        self,
        user_id: str | None = None,
        category: TemplateCategory | None = None,
        search_query: str | None = None,
        include_private: bool = False,
        page: int = 1,
        page_size: int = 20,
    ) -> tuple[list[FlowTemplate], int]:
        """
        List templates with filtering, search, and pagination.
        Returns (templates, total_count).
        """
        results = list(self._store.values())

        # Visibility filter
        if not include_private:
            results = [t for t in results if t.is_public]
        elif user_id:
            results = [
                t for t in results
                if t.is_public or t.author_id == user_id
            ]

        # Category filter
        if category:
            results = [t for t in results if t.category == category]

        # Search (name, description, tags)
        if search_query:
            query_lower = search_query.lower()
            results = [
                t for t in results
                if query_lower in t.name.lower()
                or query_lower in t.description.lower()
                or any(query_lower in tag.lower() for tag in t.tags)
            ]

        # Sort by use_count descending (most popular first)
        results.sort(key=lambda t: t.use_count, reverse=True)

        total = len(results)
        start = (page - 1) * page_size
        end = start + page_size
        return results[start:end], total

    def clone_template(
        self,
        template_id: str,
        user_id: str,
        flow_name: str | None = None,
    ) -> Flow:
        """Clone a template into a new Flow for the user."""
        self._check_rate_limit(user_id)

        template = self.get_template(template_id, user_id)
        flow = template.clone_to_flow(owner_id=user_id, name=flow_name)

        # Track usage
        template.use_count += 1
        self._record_clone(user_id)

        logger.info(
            f"Template '{template_id}' cloned to flow '{flow.flow_id}' by '{user_id}'"
        )
        return flow

    def delete_template(self, template_id: str, user_id: str) -> None:
        """Delete a template. Only the author can delete."""
        template = self.get_template(template_id, user_id)
        if template.author_id != user_id:
            raise TemplatePermissionError(
                f"User '{user_id}' is not the author of template '{template_id}'"
            )
        del self._store[template_id]
        logger.info(f"Template '{template_id}' deleted by '{user_id}'")

    def update_template(
        self,
        template_id: str,
        user_id: str,
        updates: dict[str, Any],
    ) -> FlowTemplate:
        """Update a template's metadata. Only the author can update."""
        template = self.get_template(template_id, user_id)
        if template.author_id != user_id:
            raise TemplatePermissionError(
                f"User '{user_id}' is not the author of template '{template_id}'"
            )

        allowed_fields = {"name", "description", "category", "tags", "is_public"}
        for key, value in updates.items():
            if key in allowed_fields:
                setattr(template, key, value)

        # Re-validate after updates
        errors = self._validate_template(template)
        if errors:
            raise TemplateValidationError(errors)

        return template

    def _validate_template(self, template: FlowTemplate) -> list[str]:
        errors = []

        if not template.name or not template.name.strip():
            errors.append("Template name is required")
        elif not self.ALLOWED_NAME_PATTERN.match(template.name):
            errors.append(
                "Template name must be 1-100 characters, "
                "alphanumeric, spaces, hyphens, dots only"
            )

        if not template.nodes:
            errors.append("Template must contain at least one node")

        node_ids = [n.node_id for n in template.nodes]
        if len(node_ids) != len(set(node_ids)):
            errors.append("Template contains duplicate node IDs")

        node_id_set = set(node_ids)
        for edge in template.edges:
            if edge.source_node_id not in node_id_set:
                errors.append(f"Edge references unknown source: {edge.source_node_id}")
            if edge.target_node_id not in node_id_set:
                errors.append(f"Edge references unknown target: {edge.target_node_id}")

        if len(template.tags) > 10:
            errors.append("Maximum 10 tags allowed")

        for tag in template.tags:
            if len(tag) > 30:
                errors.append(f"Tag '{tag[:20]}...' exceeds 30 character limit")

        return errors

    def _check_rate_limit(self, user_id: str) -> None:
        now = datetime.utcnow()
        timestamps = self._clone_log.get(user_id, [])
        # Keep only timestamps from the last hour
        recent = [ts for ts in timestamps if (now - ts).total_seconds() < 3600]
        self._clone_log[user_id] = recent

        if len(recent) >= self.MAX_CLONES_PER_HOUR:
            raise RateLimitError(user_id, self.MAX_CLONES_PER_HOUR)

    def _record_clone(self, user_id: str) -> None:
        if user_id not in self._clone_log:
            self._clone_log[user_id] = []
        self._clone_log[user_id].append(datetime.utcnow())
