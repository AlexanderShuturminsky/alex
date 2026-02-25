// API client for template operations

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
  category: "marketing" | "sales" | "support" | "data_processing" | "custom";
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
  status: "draft" | "active" | "paused" | "error";
  ownerId: string;
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

class TemplateApiError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
    this.name = "TemplateApiError";
  }
}

async function handleResponse<T>(response: Response): Promise<T> {
  if (!response.ok) {
    const body = await response.json().catch(() => ({ error: response.statusText }));
    throw new TemplateApiError(response.status, body.error || response.statusText);
  }
  return response.json();
}

export async function fetchTemplates(
  filters: TemplateFilters = {},
): Promise<PaginatedResponse<FlowTemplate>> {
  const params = new URLSearchParams();
  if (filters.category) params.set("category", filters.category);
  if (filters.search) params.set("search", filters.search);
  if (filters.page) params.set("page", String(filters.page));
  if (filters.pageSize) params.set("page_size", String(filters.pageSize));

  const response = await fetch(`${API_BASE}/templates?${params}`);
  return handleResponse(response);
}

export async function fetchTemplate(templateId: string): Promise<FlowTemplate> {
  const response = await fetch(`${API_BASE}/templates/${templateId}`);
  return handleResponse(response);
}

export async function cloneTemplate(
  templateId: string,
  flowName?: string,
): Promise<Flow> {
  const response = await fetch(`${API_BASE}/templates/${templateId}/clone`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ flowName }),
  });
  return handleResponse(response);
}

export async function deleteTemplate(templateId: string): Promise<void> {
  const response = await fetch(`${API_BASE}/templates/${templateId}`, {
    method: "DELETE",
  });
  if (!response.ok) {
    const body = await response.json().catch(() => ({ error: response.statusText }));
    throw new TemplateApiError(response.status, body.error || response.statusText);
  }
}
