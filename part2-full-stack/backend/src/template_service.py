"""Template service — manages CRUD, search, clone."""

import re
import logging
from datetime import datetime
from typing import Any

from src.models import FlowTemplate, Flow, TemplateCategory

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
        super().__init__(f"Rate limit exceeded: {limit} clones/hour")


class TemplateService:
    MAX_CLONES_PER_HOUR = 10
    ALLOWED_NAME_PATTERN = re.compile(r"^[\w\s\-\.]{1,100}$")

    def __init__(self, store: dict[str, FlowTemplate] | None = None):
        self._store: dict[str, FlowTemplate] = store or {}
        self._clone_log: dict[str, list[datetime]] = {}

    def create_template(self, template: FlowTemplate, user_id: str) -> FlowTemplate:
        errors = self._validate(template)
        if errors:
            raise TemplateValidationError(errors)
        template.author_id = user_id
        template.created_at = datetime.utcnow()
        self._store[template.template_id] = template
        return template

    def get_template(self, template_id: str, user_id: str | None = None) -> FlowTemplate:
        template = self._store.get(template_id)
        if not template:
            raise TemplateNotFoundError(f"Template '{template_id}' not found")
        if not template.is_public and template.author_id != user_id:
            raise TemplatePermissionError("Access denied")
        return template

    def list_templates(
        self, category: TemplateCategory | None = None,
        search_query: str | None = None, page: int = 1, page_size: int = 20,
    ) -> tuple[list[FlowTemplate], int]:
        results = [t for t in self._store.values() if t.is_public]
        if category:
            results = [t for t in results if t.category == category]
        if search_query:
            q = search_query.lower()
            results = [
                t for t in results
                if q in t.name.lower() or q in t.description.lower()
                or any(q in tag.lower() for tag in t.tags)
            ]
        results.sort(key=lambda t: t.use_count, reverse=True)
        total = len(results)
        start = (page - 1) * page_size
        return results[start:start + page_size], total

    def clone_template(self, template_id: str, user_id: str, flow_name: str | None = None) -> Flow:
        self._check_rate_limit(user_id)
        template = self.get_template(template_id, user_id)
        flow = template.clone_to_flow(owner_id=user_id, name=flow_name)
        template.use_count += 1
        self._record_clone(user_id)
        return flow

    def delete_template(self, template_id: str, user_id: str) -> None:
        template = self.get_template(template_id, user_id)
        if template.author_id != user_id:
            raise TemplatePermissionError("Only the author can delete")
        del self._store[template_id]

    def _validate(self, template: FlowTemplate) -> list[str]:
        errors = []
        if not template.name or not template.name.strip():
            errors.append("Template name is required")
        elif not self.ALLOWED_NAME_PATTERN.match(template.name):
            errors.append("Invalid template name")
        if not template.nodes:
            errors.append("Template must contain at least one node")
        if len(template.tags) > 10:
            errors.append("Maximum 10 tags allowed")
        return errors

    def _check_rate_limit(self, user_id: str) -> None:
        now = datetime.utcnow()
        recent = [ts for ts in self._clone_log.get(user_id, []) if (now - ts).total_seconds() < 3600]
        self._clone_log[user_id] = recent
        if len(recent) >= self.MAX_CLONES_PER_HOUR:
            raise RateLimitError(user_id, self.MAX_CLONES_PER_HOUR)

    def _record_clone(self, user_id: str) -> None:
        self._clone_log.setdefault(user_id, []).append(datetime.utcnow())
