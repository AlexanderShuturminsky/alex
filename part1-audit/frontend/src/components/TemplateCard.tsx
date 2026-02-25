import React, { useState } from "react";
import type { FlowTemplate } from "../api/templates";

interface TemplateCardProps {
  template: FlowTemplate;
  onClone: (templateId: string, flowName?: string) => Promise<unknown>;
  onDelete?: (templateId: string) => Promise<boolean>;
  isCloning?: boolean;
  isOwner?: boolean;
}

const CATEGORY_COLORS: Record<string, string> = {
  marketing: "bg-purple-100 text-purple-800",
  sales: "bg-blue-100 text-blue-800",
  support: "bg-green-100 text-green-800",
  data_processing: "bg-orange-100 text-orange-800",
  custom: "bg-gray-100 text-gray-800",
};

export function TemplateCard({
  template,
  onClone,
  onDelete,
  isCloning = false,
  isOwner = false,
}: TemplateCardProps) {
  const [showCloneModal, setShowCloneModal] = useState(false);
  const [flowName, setFlowName] = useState(`Copy of ${template.name}`);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);

  const handleClone = async () => {
    await onClone(template.templateId, flowName);
    setShowCloneModal(false);
    setFlowName(`Copy of ${template.name}`);
  };

  const handleDelete = async () => {
    if (onDelete) {
      const success = await onDelete(template.templateId);
      if (success) setShowDeleteConfirm(false);
    }
  };

  const categoryClass = CATEGORY_COLORS[template.category] || CATEGORY_COLORS.custom;

  return (
    <div
      className="border rounded-lg p-4 hover:shadow-md transition-shadow"
      data-testid={`template-card-${template.templateId}`}
    >
      <div className="flex justify-between items-start mb-2">
        <h3 className="font-semibold text-lg truncate" title={template.name}>
          {template.name}
        </h3>
        <span className={`text-xs px-2 py-1 rounded-full ${categoryClass}`}>
          {template.category.replace("_", " ")}
        </span>
      </div>

      <p className="text-gray-600 text-sm mb-3 line-clamp-2">{template.description}</p>

      {template.tags.length > 0 && (
        <div className="flex flex-wrap gap-1 mb-3">
          {template.tags.map((tag) => (
            <span
              key={tag}
              className="text-xs bg-gray-100 text-gray-600 px-2 py-0.5 rounded"
            >
              {tag}
            </span>
          ))}
        </div>
      )}

      <div className="flex items-center justify-between text-sm text-gray-500 mb-3">
        <span>{template.nodes.length} nodes</span>
        <span>{template.useCount.toLocaleString()} uses</span>
      </div>

      <div className="flex gap-2">
        <button
          onClick={() => setShowCloneModal(true)}
          disabled={isCloning}
          className="flex-1 bg-blue-600 text-white py-2 px-4 rounded hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
          data-testid="clone-button"
        >
          {isCloning ? "Cloning..." : "Use Template"}
        </button>

        {isOwner && onDelete && (
          <button
            onClick={() => setShowDeleteConfirm(true)}
            className="text-red-600 hover:text-red-800 py-2 px-3 rounded border border-red-200 hover:border-red-400"
            data-testid="delete-button"
            aria-label={`Delete template ${template.name}`}
          >
            Delete
          </button>
        )}
      </div>

      {/* Clone Modal */}
      {showCloneModal && (
        <div
          className="fixed inset-0 bg-black/50 flex items-center justify-center z-50"
          data-testid="clone-modal"
          onClick={(e) => {
            if (e.target === e.currentTarget) setShowCloneModal(false);
          }}
        >
          <div className="bg-white rounded-lg p-6 w-96 max-w-[90vw]">
            <h4 className="font-semibold text-lg mb-4">Clone Template</h4>
            <label className="block text-sm text-gray-600 mb-1">Flow Name</label>
            <input
              type="text"
              value={flowName}
              onChange={(e) => setFlowName(e.target.value)}
              className="w-full border rounded px-3 py-2 mb-4"
              data-testid="flow-name-input"
              maxLength={100}
              autoFocus
            />
            <div className="flex gap-2 justify-end">
              <button
                onClick={() => setShowCloneModal(false)}
                className="px-4 py-2 text-gray-600 hover:text-gray-800"
                data-testid="cancel-clone"
              >
                Cancel
              </button>
              <button
                onClick={handleClone}
                disabled={!flowName.trim() || isCloning}
                className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50"
                data-testid="confirm-clone"
              >
                {isCloning ? "Cloning..." : "Create Flow"}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Delete Confirmation */}
      {showDeleteConfirm && (
        <div
          className="fixed inset-0 bg-black/50 flex items-center justify-center z-50"
          data-testid="delete-confirm-modal"
        >
          <div className="bg-white rounded-lg p-6 w-96">
            <h4 className="font-semibold text-lg mb-2">Delete Template</h4>
            <p className="text-gray-600 mb-4">
              Are you sure you want to delete &quot;{template.name}&quot;? This
              action cannot be undone.
            </p>
            <div className="flex gap-2 justify-end">
              <button
                onClick={() => setShowDeleteConfirm(false)}
                className="px-4 py-2 text-gray-600"
                data-testid="cancel-delete"
              >
                Cancel
              </button>
              <button
                onClick={handleDelete}
                className="px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700"
                data-testid="confirm-delete"
              >
                Delete
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
