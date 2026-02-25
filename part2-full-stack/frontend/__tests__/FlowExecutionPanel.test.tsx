/**
 * Component tests for FlowExecutionPanel.
 *
 * Write tests that verify:
 * - Initial render state (run button visible, no results)
 * - Trigger data JSON input and validation
 * - Running a flow (button states, loading indicators)
 * - Displaying node results (success, failed, skipped)
 * - Expanding/collapsing node result details
 * - Error display (API errors, validation errors)
 * - Cancel button appears during execution
 * - Reset / "Run Again" after completion
 * - Execution summary (total time, success count)
 *
 * Use React Testing Library. Mock the useFlowExecution hook or the API client.
 */

import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { FlowExecutionPanel } from "../src/components/FlowExecutionPanel";
import type { FlowRun, NodeResult } from "../src/api/client";

// ---------------------------------------------------------------------------
// Test data factories
// ---------------------------------------------------------------------------

function makeNodeResult(overrides: Partial<NodeResult> = {}): NodeResult {
  return {
    nodeId: "node-1",
    output: { result: "test output" },
    executionTimeMs: 150,
    status: "success",
    error: null,
    ...overrides,
  };
}

function makeFlowRun(overrides: Partial<FlowRun> = {}): FlowRun {
  return {
    runId: "run-1",
    flowId: "flow-1",
    ownerId: "user-1",
    status: "completed",
    triggerData: { text: "hello" },
    nodeResults: [
      makeNodeResult({ nodeId: "trigger-1" }),
      makeNodeResult({ nodeId: "ai-1", executionTimeMs: 500 }),
      makeNodeResult({ nodeId: "output-1", executionTimeMs: 50 }),
    ],
    totalTimeMs: 700,
    error: null,
    createdAt: "2025-01-01T00:00:00Z",
    completedAt: "2025-01-01T00:00:01Z",
    ...overrides,
  };
}

const defaultProps = {
  flowId: "flow-1",
  flowName: "Email Automation",
  nodeLabels: {
    "trigger-1": "Gmail Trigger",
    "ai-1": "AI Summarize",
    "output-1": "Slack Output",
  },
};

// ---------------------------------------------------------------------------
// Your component tests go here
// ---------------------------------------------------------------------------
