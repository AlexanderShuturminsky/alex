/**
 * End-to-end tests using Playwright.
 *
 * These tests run against the full application (backend + frontend).
 * Write tests that verify complete user flows:
 *
 * 1. Template Gallery Flow:
 *    - Load gallery → see templates → search → filter by category
 *    - Clone a template → get redirected to the new flow
 *    - Delete a template (as owner)
 *
 * 2. Flow Execution Flow:
 *    - Open a flow → enter trigger data → click Run
 *    - See running state with cancel button
 *    - See completed results with per-node status
 *    - Expand a node to see output details
 *    - Click "Run Again" to reset
 *
 * 3. Error Flows:
 *    - Run a flow with invalid trigger data JSON
 *    - Run a flow that fails mid-execution → see error state
 *    - Try to clone when rate limited → see 429 error
 *
 * 4. Auth / Permissions:
 *    - Try to delete a template you don't own → see error
 *    - Try to run another user's flow → see 403
 *
 * Assume the app is running at http://localhost:3000 with the API at
 * http://localhost:5001. Use Playwright's API request context for
 * seeding test data.
 */

import { test, expect, type Page } from "@playwright/test";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const APP_URL = "http://localhost:3000";
const API_URL = "http://localhost:5001/api/v1";

/**
 * Seed a template via the API for testing.
 */
async function seedTemplate(
  request: any,
  userId: string = "test-user",
  overrides: Record<string, unknown> = {},
) {
  const payload = {
    name: "Test Template",
    description: "A seeded test template",
    category: "marketing",
    nodes: [
      {
        nodeId: "trigger-1",
        nodeType: "trigger",
        label: "Webhook",
        params: { trigger_type: "webhook" },
      },
      {
        nodeId: "ai-1",
        nodeType: "ai_transform",
        label: "AI Summarize",
        params: {
          model: "claude-sonnet-4-20250514",
          prompt_template: "Summarize: {text}",
        },
      },
      {
        nodeId: "output-1",
        nodeType: "output",
        label: "Output",
        params: { destination: "slack" },
      },
    ],
    edges: [
      { sourceNodeId: "trigger-1", targetNodeId: "ai-1" },
      { sourceNodeId: "ai-1", targetNodeId: "output-1" },
    ],
    tags: ["test"],
    isPublic: true,
    ...overrides,
  };

  const response = await request.post(`${API_URL}/templates`, {
    data: payload,
    headers: { "X-User-Id": userId, "Content-Type": "application/json" },
  });

  return response.json();
}

// ---------------------------------------------------------------------------
// Your E2E tests go here
// ---------------------------------------------------------------------------
