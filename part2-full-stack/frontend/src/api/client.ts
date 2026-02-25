// API client for templates and flow execution

export interface NodeConfig {
  nodeId: string;
  nodeType: string;
  label: string;
  params: Record<string, unknown>;
  position: { x: number; y: number };
}

export interface Edge {
  sourceNodeId: string;
  targetNodeId: string;
  sourceOutput: string;
  targetInput: string;
}

export interface FlowTemplate {
  templateId: string;
  name: string;
  description: string;
  category: string;
  nodes: NodeConfig[];
  edges: Edge[];
  authorId: string | null;
  isPublic: boolean;
  useCount: number;
  tags: string[];
  createdAt: string;
}

export interface Flow {
  flowId: string;
  name: string;
  nodes: NodeConfig[];
  edges: Edge[];
  status: string;
  ownerId: string;
}

export interface NodeResult {
  nodeId: string;
  output: Record<string, unknown>;
  executionTimeMs: number;
  status: "success" | "failed" | "skipped" | "cancelled";
  error: string | null;
}

export interface FlowRun {
  runId: string;
  flowId: string;
  ownerId: string;
  status: "pending" | "running" | "completed" | "failed" | "cancelled";
  triggerData: Record<string, unknown>;
  nodeResults: NodeResult[];
  totalTimeMs: number;
  error: string | null;
  createdAt: string;
  completedAt: string | null;
}

export interface PaginatedResponse<T> {
  items: T[];
  total: number;
  page: number;
  pageSize: number;
}

export interface TemplateFilters {
  category?: string;
  search?: string;
  page?: number;
  pageSize?: number;
}

const API_BASE = "/api/v1";
const DEV_USER = "user-dev";

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

function authHeaders(extra: Record<string, string> = {}): Record<string, string> {
  return { "X-User-Id": DEV_USER, ...extra };
}

async function handleResponse<T>(response: Response): Promise<T> {
  if (!response.ok) {
    const body = await response.json().catch(() => ({ error: response.statusText }));
    throw new ApiError(response.status, body.error || response.statusText);
  }
  return response.json();
}

// --- Templates ---

export async function fetchTemplates(
  filters: TemplateFilters = {},
): Promise<PaginatedResponse<FlowTemplate>> {
  const params = new URLSearchParams();
  if (filters.category) params.set("category", filters.category);
  if (filters.search) params.set("search", filters.search);
  if (filters.page) params.set("page", String(filters.page));
  if (filters.pageSize) params.set("page_size", String(filters.pageSize));

  const response = await fetch(`${API_BASE}/templates?${params}`, {
    headers: authHeaders(),
  });
  return handleResponse(response);
}

export async function fetchTemplate(templateId: string): Promise<FlowTemplate> {
  const response = await fetch(`${API_BASE}/templates/${templateId}`, {
    headers: authHeaders(),
  });
  return handleResponse(response);
}

export async function cloneTemplate(
  templateId: string,
  flowName?: string,
): Promise<Flow> {
  const response = await fetch(`${API_BASE}/templates/${templateId}/clone`, {
    method: "POST",
    headers: authHeaders({ "Content-Type": "application/json" }),
    body: JSON.stringify({ flowName }),
  });
  return handleResponse(response);
}

export async function deleteTemplate(templateId: string): Promise<void> {
  const response = await fetch(`${API_BASE}/templates/${templateId}`, {
    method: "DELETE",
    headers: authHeaders(),
  });
  if (!response.ok) {
    const body = await response.json().catch(() => ({ error: response.statusText }));
    throw new ApiError(response.status, body.error || response.statusText);
  }
}

// --- Flow Execution ---

export async function runFlow(
  flowId: string,
  triggerData: Record<string, unknown> = {},
): Promise<FlowRun> {
  const response = await fetch(`${API_BASE}/flows/${flowId}/run`, {
    method: "POST",
    headers: authHeaders({ "Content-Type": "application/json" }),
    body: JSON.stringify({ triggerData }),
  });
  return handleResponse(response);
}

export async function getFlowRun(runId: string): Promise<FlowRun> {
  const response = await fetch(`${API_BASE}/runs/${runId}`, {
    headers: authHeaders(),
  });
  return handleResponse(response);
}

export async function cancelFlowRun(runId: string): Promise<FlowRun> {
  const response = await fetch(`${API_BASE}/runs/${runId}/cancel`, {
    method: "POST",
    headers: authHeaders(),
  });
  return handleResponse(response);
}
