import React from "react";
import { useTemplates } from "../hooks/useTemplates";
import { TemplateCard } from "./TemplateCard";

const CATEGORIES = [
  { value: "", label: "All Categories" },
  { value: "marketing", label: "Marketing" },
  { value: "sales", label: "Sales" },
  { value: "support", label: "Support" },
  { value: "data_processing", label: "Data Processing" },
  { value: "custom", label: "Custom" },
] as const;

interface TemplateGalleryProps {
  currentUserId?: string;
  onFlowCreated?: (flowId: string) => void;
}

export function TemplateGallery({
  currentUserId,
  onFlowCreated,
}: TemplateGalleryProps) {
  const {
    templates,
    total,
    loading,
    error,
    cloning,
    filters,
    setFilters,
    clone,
    remove,
    refresh,
  } = useTemplates({ page: 1, pageSize: 12 });

  const totalPages = Math.ceil(total / (filters.pageSize || 12));

  const handleClone = async (templateId: string, flowName?: string) => {
    const flow = await clone(templateId, flowName);
    if (flow && onFlowCreated) {
      onFlowCreated(flow.flowId);
    }
  };

  const handleSearch = (e: React.ChangeEvent<HTMLInputElement>) => {
    setFilters({ ...filters, search: e.target.value, page: 1 });
  };

  const handleCategoryChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
    setFilters({ ...filters, category: e.target.value || undefined, page: 1 });
  };

  const handlePageChange = (newPage: number) => {
    setFilters({ ...filters, page: newPage });
  };

  return (
    <div className="max-w-6xl mx-auto p-6" data-testid="template-gallery">
      {/* Header */}
      <div className="flex justify-between items-center mb-6">
        <h2 className="text-2xl font-bold">Template Gallery</h2>
        <button
          onClick={refresh}
          className="text-sm text-blue-600 hover:text-blue-800"
          data-testid="refresh-button"
        >
          Refresh
        </button>
      </div>

      {/* Filters */}
      <div className="flex gap-4 mb-6">
        <input
          type="text"
          placeholder="Search templates..."
          value={filters.search || ""}
          onChange={handleSearch}
          className="flex-1 border rounded px-4 py-2"
          data-testid="search-input"
        />
        <select
          value={filters.category || ""}
          onChange={handleCategoryChange}
          className="border rounded px-4 py-2"
          data-testid="category-select"
        >
          {CATEGORIES.map((cat) => (
            <option key={cat.value} value={cat.value}>
              {cat.label}
            </option>
          ))}
        </select>
      </div>

      {/* Error State */}
      {error && (
        <div
          className="bg-red-50 border border-red-200 text-red-700 p-4 rounded mb-6"
          data-testid="error-message"
          role="alert"
        >
          <p>{error}</p>
          <button
            onClick={refresh}
            className="text-sm underline mt-2"
            data-testid="retry-button"
          >
            Try again
          </button>
        </div>
      )}

      {/* Loading State */}
      {loading && (
        <div className="flex justify-center py-12" data-testid="loading-spinner">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600" />
        </div>
      )}

      {/* Empty State */}
      {!loading && !error && templates.length === 0 && (
        <div className="text-center py-12 text-gray-500" data-testid="empty-state">
          <p className="text-lg mb-2">No templates found</p>
          {filters.search && (
            <p className="text-sm">
              Try a different search term or{" "}
              <button
                onClick={() => setFilters({ ...filters, search: "", page: 1 })}
                className="text-blue-600 hover:underline"
                data-testid="clear-search"
              >
                clear the search
              </button>
            </p>
          )}
        </div>
      )}

      {/* Template Grid */}
      {!loading && templates.length > 0 && (
        <>
          <div
            className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mb-6"
            data-testid="template-grid"
          >
            {templates.map((template) => (
              <TemplateCard
                key={template.templateId}
                template={template}
                onClone={handleClone}
                onDelete={currentUserId ? remove : undefined}
                isCloning={cloning === template.templateId}
                isOwner={template.authorId === currentUserId}
              />
            ))}
          </div>

          {/* Pagination */}
          {totalPages > 1 && (
            <div
              className="flex justify-center gap-2"
              data-testid="pagination"
            >
              <button
                onClick={() => handlePageChange((filters.page || 1) - 1)}
                disabled={filters.page === 1}
                className="px-3 py-1 border rounded disabled:opacity-50"
                data-testid="prev-page"
              >
                Previous
              </button>
              <span className="px-3 py-1 text-sm text-gray-600">
                Page {filters.page || 1} of {totalPages}
              </span>
              <button
                onClick={() => handlePageChange((filters.page || 1) + 1)}
                disabled={(filters.page || 1) >= totalPages}
                className="px-3 py-1 border rounded disabled:opacity-50"
                data-testid="next-page"
              >
                Next
              </button>
            </div>
          )}
        </>
      )}
    </div>
  );
}
