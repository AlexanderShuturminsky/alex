import React, { useState } from "react";
import { useFlowExecution } from "../hooks/useFlowExecution";
import type { FlowRun, NodeResult } from "../api/client";

interface FlowExecutionPanelProps {
  flowId: string;
  flowName: string;
  nodeLabels: Record<string, string>; // nodeId → label
  defaultTriggerData?: string;
}

const STATUS_STYLES: Record<string, string> = {
  success: "bg-green-100 text-green-800",
  failed: "bg-red-100 text-red-800",
  skipped: "bg-gray-100 text-gray-500",
  cancelled: "bg-yellow-100 text-yellow-800",
  running: "bg-blue-100 text-blue-800",
  pending: "bg-gray-100 text-gray-600",
  completed: "bg-green-100 text-green-800",
};

export function FlowExecutionPanel({
  flowId,
  flowName,
  nodeLabels,
  defaultTriggerData,
}: FlowExecutionPanelProps) {
  const { currentRun, isRunning, error, execute, cancel, reset } =
    useFlowExecution();
  const [triggerInput, setTriggerInput] = useState(defaultTriggerData ?? "{}");
  const [inputError, setInputError] = useState<string | null>(null);

  const handleRun = async () => {
    setInputError(null);
    try {
      const triggerData = JSON.parse(triggerInput);
      await execute(flowId, triggerData);
    } catch (err) {
      if (err instanceof SyntaxError) {
        setInputError("Invalid JSON");
      }
    }
  };

  const statusStyle = currentRun
    ? STATUS_STYLES[currentRun.status] || ""
    : "";

  return (
    <div className="border rounded-lg p-6" data-testid="execution-panel">
      {/* Header */}
      <div className="flex justify-between items-center mb-4">
        <h3 className="text-lg font-semibold">{flowName}</h3>
        {currentRun && (
          <span
            className={`text-xs px-2 py-1 rounded-full font-medium ${statusStyle}`}
            data-testid="run-status"
          >
            {currentRun.status.toUpperCase()}
          </span>
        )}
      </div>

      {/* Trigger Data Input */}
      {!currentRun && (
        <div className="mb-4">
          <label className="block text-sm text-gray-600 mb-1">
            Trigger Data (JSON)
          </label>
          <textarea
            value={triggerInput}
            onChange={(e) => setTriggerInput(e.target.value)}
            className="w-full border rounded px-3 py-2 font-mono text-sm h-24"
            data-testid="trigger-input"
            placeholder='{"email_body": "Hello...", "sender": "user@example.com"}'
          />
          {inputError && (
            <p className="text-red-600 text-sm mt-1\" data-testid="input-error">
              {inputError}
            </p>
          )}
        </div>
      )}

      {/* Action Buttons */}
      <div className="flex gap-2 mb-4">
        {!isRunning && !currentRun && (
          <button
            onClick={handleRun}
            className="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700"
            data-testid="run-button"
          >
            Run Flow
          </button>
        )}
        {isRunning && (
          <button
            onClick={cancel}
            className="bg-red-600 text-white px-4 py-2 rounded hover:bg-red-700"
            data-testid="cancel-button"
          >
            Cancel
          </button>
        )}
        {currentRun && !isRunning && (
          <button
            onClick={reset}
            className="bg-gray-200 text-gray-700 px-4 py-2 rounded hover:bg-gray-300"
            data-testid="reset-button"
          >
            Run Again
          </button>
        )}
      </div>

      {/* Error Display */}
      {(error || currentRun?.error) && (
        <div
          className="bg-red-50 border border-red-200 text-red-700 p-3 rounded mb-4"
          data-testid="error-display"
          role="alert"
        >
          {error || currentRun?.error}
        </div>
      )}

      {/* Node Results */}
      {currentRun && currentRun.nodeResults.length > 0 && (
        <div data-testid="node-results">
          <h4 className="font-medium text-sm text-gray-600 mb-2">
            Node Results
          </h4>
          <div className="space-y-2">
            {currentRun.nodeResults.map((result) => (
              <NodeResultRow
                key={result.nodeId}
                result={result}
                label={nodeLabels[result.nodeId] || result.nodeId}
              />
            ))}
          </div>
        </div>
      )}

      {/* Execution Summary */}
      {currentRun && !isRunning && (
        <div
          className="mt-4 pt-4 border-t text-sm text-gray-500"
          data-testid="execution-summary"
        >
          <span>Total time: {currentRun.totalTimeMs.toFixed(0)}ms</span>
          <span className="mx-2">·</span>
          <span>
            {currentRun.nodeResults.filter((r) => r.status === "success").length}/
            {currentRun.nodeResults.length} nodes succeeded
          </span>
        </div>
      )}
    </div>
  );
}

function NodeResultRow({
  result,
  label,
}: {
  result: NodeResult;
  label: string;
}) {
  const [expanded, setExpanded] = useState(false);
  const statusStyle = STATUS_STYLES[result.status] || "";

  return (
    <div className="border rounded p-3" data-testid={`node-result-${result.nodeId}`}>
      <div
        className="flex justify-between items-center cursor-pointer"
        onClick={() => setExpanded(!expanded)}
        data-testid={`node-result-toggle-${result.nodeId}`}
      >
        <div className="flex items-center gap-2">
          <span className={`text-xs px-2 py-0.5 rounded ${statusStyle}`}>
            {result.status}
          </span>
          <span className="font-medium text-sm">{label}</span>
        </div>
        <span className="text-xs text-gray-400">
          {result.executionTimeMs.toFixed(0)}ms
        </span>
      </div>

      {expanded && (
        <div className="mt-2 pt-2 border-t" data-testid={`node-result-detail-${result.nodeId}`}>
          {result.error ? (
            <p className="text-red-600 text-sm">{result.error}</p>
          ) : (
            <pre className="text-xs bg-gray-50 p-2 rounded overflow-x-auto">
              {JSON.stringify(result.output, null, 2)}
            </pre>
          )}
        </div>
      )}
    </div>
  );
}
