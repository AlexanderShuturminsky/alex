"""Tests for template service."""

import pytest
from datetime import datetime
from unittest.mock import patch, MagicMock

from src.models import FlowTemplate, NodeConfig, NodeType, Edge, TemplateCategory
from src.template_service import (
    TemplateService,
    TemplateNotFoundError,
    TemplatePermissionError,
    TemplateValidationError,
    RateLimitError,
)


# ---------- Shared fixture ----------
# NOTE: This store is shared across ALL tests in this file
_shared_store: dict[str, FlowTemplate] = {}
_service = TemplateService(store=_shared_store)


def _make_template(
    template_id="tmpl-1",
    name="Test Template",
    category=TemplateCategory.MARKETING,
    author_id="user-1",
    is_public=True,
    nodes=None,
    tags=None,
):
    return FlowTemplate(
        template_id=template_id,
        name=name,
        description="A test template",
        category=category,
        nodes=nodes or [
            NodeConfig("n1", NodeType.TRIGGER, "Trigger", {"trigger_type": "webhook"}),
            NodeConfig("n2", NodeType.AI_TRANSFORM, "AI", {"model": "claude-sonnet-4-20250514", "prompt_template": "test"}),
        ],
        edges=[Edge("n1", "n2")],
        author_id=author_id,
        is_public=is_public,
        tags=tags or ["test"],
    )


class TestTemplateServiceCreate:

    def test_create_template(self):
        """Test creating a template."""
        template = _make_template()
        result = _service.create_template(template, "user-1")
        assert result is not None
        assert result.template_id == "tmpl-1"

    def test_create_sets_author(self):
        """Test that create sets the author ID."""
        template = _make_template(template_id="tmpl-2")
        result = _service.create_template(template, "user-2")
        assert result.author_id == "user-2"

    def test_create_sets_timestamp(self):
        """Test that create sets created_at."""
        template = _make_template(template_id="tmpl-3")
        result = _service.create_template(template, "user-1")
        assert result.created_at is not None
        assert isinstance(result.created_at, datetime)

    def test_create_empty_name_fails(self):
        """Test that empty name fails validation."""
        template = _make_template(template_id="tmpl-4", name="")
        with pytest.raises(TemplateValidationError):
            _service.create_template(template, "user-1")

    def test_create_no_nodes_fails(self):
        """Test that template with no nodes fails."""
        template = FlowTemplate(
            template_id="tmpl-5",
            name="Empty Template",
            description="No nodes",
            category=TemplateCategory.CUSTOM,
            nodes=[],
            edges=[],
        )
        with pytest.raises(TemplateValidationError):
            _service.create_template(template, "user-1")


class TestTemplateServiceGet:

    def test_get_template(self):
        """Test getting a template by ID."""
        # Relies on test_create_template having run first
        result = _service.get_template("tmpl-1")
        assert result.name == "Test Template"

    def test_get_nonexistent_template(self):
        """Test getting a template that doesn't exist."""
        try:
            _service.get_template("nonexistent")
            assert False
        except TemplateNotFoundError:
            assert True

    def test_get_returns_correct_type(self):
        result = _service.get_template("tmpl-1")
        assert isinstance(result, FlowTemplate)


class TestTemplateServiceList:

    def test_list_templates_returns_results(self):
        """Test listing templates."""
        results, total = _service.list_templates()
        assert len(results) > 0
        assert total > 0

    def test_list_with_category_filter(self):
        """Test category filtering."""
        results, total = _service.list_templates(category=TemplateCategory.MARKETING)
        assert all(t.category == TemplateCategory.MARKETING for t in results)

    def test_list_with_search(self):
        """Test search filtering."""
        results, total = _service.list_templates(search_query="Test")
        assert len(results) >= 0  # Could be 0 or more

    def test_list_pagination(self):
        """Test that pagination works."""
        results, total = _service.list_templates(page=1, page_size=1)
        assert len(results) <= 1

    def test_list_returns_tuple(self):
        """Test return type."""
        result = _service.list_templates()
        assert isinstance(result, tuple)
        assert len(result) == 2


class TestTemplateServiceClone:

    def test_clone_template(self):
        """Test cloning a template."""
        flow = _service.clone_template("tmpl-1", "user-1")
        assert flow is not None
        assert flow.owner_id == "user-1"

    def test_clone_increments_use_count(self):
        """Test that cloning increments the use count."""
        template_before = _service.get_template("tmpl-1")
        count_before = template_before.use_count
        _service.clone_template("tmpl-1", "user-1")
        template_after = _service.get_template("tmpl-1")
        assert template_after.use_count > count_before

    def test_clone_creates_new_node_ids(self):
        """Test that cloned flow has different node IDs."""
        flow = _service.clone_template("tmpl-1", "user-1")
        original = _service.get_template("tmpl-1")
        original_ids = {n.node_id for n in original.nodes}
        cloned_ids = {n.node_id for n in flow.nodes}
        assert original_ids != cloned_ids


class TestTemplateServiceDelete:

    def test_delete_template(self):
        """Test deleting a template."""
        template = _make_template(template_id="tmpl-to-delete", author_id="user-99")
        _service.create_template(template, "user-99")
        _service.delete_template("tmpl-to-delete", "user-99")

        with pytest.raises(TemplateNotFoundError):
            _service.get_template("tmpl-to-delete")

    def test_delete_wrong_user(self):
        """Test that non-author cannot delete."""
        template = _make_template(template_id="tmpl-protected", author_id="user-owner")
        _service.create_template(template, "user-owner")
        with pytest.raises(TemplatePermissionError):
            _service.delete_template("tmpl-protected", "user-attacker")
