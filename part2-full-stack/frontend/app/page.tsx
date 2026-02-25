"use client";

import { useState, useEffect, useCallback } from "react";
import { FlowExecutionPanel } from "../src/components/FlowExecutionPanel";
import type { FlowTemplate, Flow } from "../src/api/client";
import { fetchTemplates, cloneTemplate } from "../src/api/client";

const CATEGORIES = [
  { value: "", label: "All Categories" },
  { value: "marketing", label: "Marketing" },
  { value: "sales", label: "Sales" },
  { value: "support", label: "Support" },
  { value: "data_processing", label: "Data Processing" },
  { value: "custom", label: "Custom" },
];

export default function Home() {
  const [templates, setTemplates] = useState<FlowTemplate[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [category, setCategory] = useState("");
  const [activeFlow, setActiveFlow] = useState<Flow | null>(null);
  const [cloning, setCloning] = useState<string | null>(null);

  const loadTemplates = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetchTemplates({
        search: search || undefined,
        category: category || undefined,
      });
      setTemplates(res.items);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load templates");
    } finally {
      setLoading(false);
    }
  }, [search, category]);

  useEffect(() => {
    loadTemplates();
  }, [loadTemplates]);

  const handleClone = async (templateId: string, templateName: string) => {
    setCloning(templateId);
    try {
      const flow = await cloneTemplate(templateId);
      setActiveFlow({ ...flow, name: flow.name || `Copy of ${templateName}` });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Clone failed");
    } finally {
      setCloning(null);
    }
  };

  const nodeLabels = activeFlow
    ? Object.fromEntries(activeFlow.nodes.map((n) => [n.nodeId, n.label]))
    : {};

  return (
    <main className="max-w-5xl mx-auto py-8 px-4">
      <h1 className="text-2xl font-bold mb-6">Gumloop — Template Gallery</h1>

      {/* Filters */}
      <div className="flex gap-4 mb-6">
        <input
          type="text"
          placeholder="Search templates..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="flex-1 border rounded px-4 py-2"
        />
        <select
          value={category}
          onChange={(e) => setCategory(e.target.value)}
          className="border rounded px-4 py-2"
        >
          {CATEGORIES.map((c) => (
            <option key={c.value} value={c.value}>
              {c.label}
            </option>
          ))}
        </select>
      </div>

      {error && (
        <div className="bg-red-50 border border-red-200 text-red-700 p-4 rounded mb-6">
          {error}
        </div>
      )}

      {loading && (
        <div className="flex justify-center py-12">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600" />
        </div>
      )}

      {/* Template Grid */}
      {!loading && templates.length > 0 && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mb-8">
          {templates.map((t) => (
            <div
              key={t.templateId}
              className="border rounded-lg p-4 hover:shadow-md transition-shadow"
            >
              <div className="flex justify-between items-start mb-2">
                <h3 className="font-semibold text-sm">{t.name}</h3>
                <span className="text-xs bg-gray-100 text-gray-600 px-2 py-0.5 rounded-full">
                  {t.category}
                </span>
              </div>
              <p className="text-xs text-gray-500 mb-3 line-clamp-2">
                {t.description}
              </p>
              <div className="flex items-center justify-between">
                <span className="text-xs text-gray-400">
                  {t.nodes.length} nodes · {t.useCount} uses
                </span>
                <button
                  onClick={() => handleClone(t.templateId, t.name)}
                  disabled={cloning === t.templateId}
                  className="text-xs bg-blue-600 text-white px-3 py-1 rounded hover:bg-blue-700 disabled:opacity-50"
                >
                  {cloning === t.templateId ? "Cloning..." : "Clone & Run"}
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      {!loading && templates.length === 0 && !error && (
        <p className="text-center text-gray-500 py-12">No templates found.</p>
      )}

      {/* Flow Execution Panel */}
      {activeFlow && (
        <div className="border-t pt-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-bold">
              Running: {activeFlow.name}
            </h2>
            <button
              onClick={() => setActiveFlow(null)}
              className="text-sm text-gray-500 hover:text-gray-700"
            >
              Close
            </button>
          </div>
          <FlowExecutionPanel
            flowId={activeFlow.flowId}
            flowName={activeFlow.name}
            nodeLabels={nodeLabels}
            defaultTriggerData={JSON.stringify({ text: "Hello world, summarize this for me.", sender: "user@example.com" }, null, 2)}
          />
        </div>
      )}
    </main>
  );
}
