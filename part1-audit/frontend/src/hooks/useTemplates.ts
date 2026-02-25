import { useState, useEffect, useCallback, useRef } from "react";
import {
  fetchTemplates,
  cloneTemplate,
  deleteTemplate,
  type FlowTemplate,
  type Flow,
  type TemplateFilters,
} from "../api/templates";

interface UseTemplatesState {
  templates: FlowTemplate[];
  total: number;
  loading: boolean;
  error: string | null;
  cloning: string | null; // template ID currently being cloned
}

interface UseTemplatesReturn extends UseTemplatesState {
  filters: TemplateFilters;
  setFilters: (filters: TemplateFilters) => void;
  clone: (templateId: string, flowName?: string) => Promise<Flow | null>;
  remove: (templateId: string) => Promise<boolean>;
  refresh: () => void;
}

const DEBOUNCE_MS = 300;

export function useTemplates(initialFilters: TemplateFilters = {}): UseTemplatesReturn {
  const [state, setState] = useState<UseTemplatesState>({
    templates: [],
    total: 0,
    loading: true,
    error: null,
    cloning: null,
  });
  const [filters, setFilters] = useState<TemplateFilters>(initialFilters);
  const debounceTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const abortControllerRef = useRef<AbortController | null>(null);

  const loadTemplates = useCallback(async () => {
    // Cancel any in-flight request
    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
    }
    abortControllerRef.current = new AbortController();

    setState((prev) => ({ ...prev, loading: true, error: null }));

    try {
      const response = await fetchTemplates(filters);
      setState((prev) => ({
        ...prev,
        templates: response.items,
        total: response.total,
        loading: false,
      }));
    } catch (err) {
      if (err instanceof DOMException && err.name === "AbortError") return;
      setState((prev) => ({
        ...prev,
        loading: false,
        error: err instanceof Error ? err.message : "Failed to load templates",
      }));
    }
  }, [filters]);

  // Debounced search
  useEffect(() => {
    if (debounceTimer.current) clearTimeout(debounceTimer.current);

    debounceTimer.current = setTimeout(() => {
      loadTemplates();
    }, filters.search ? DEBOUNCE_MS : 0);

    return () => {
      if (debounceTimer.current) clearTimeout(debounceTimer.current);
    };
  }, [loadTemplates, filters]);

  const clone = useCallback(
    async (templateId: string, flowName?: string): Promise<Flow | null> => {
      setState((prev) => ({ ...prev, cloning: templateId }));
      try {
        const flow = await cloneTemplate(templateId, flowName);
        // Update use_count locally
        setState((prev) => ({
          ...prev,
          cloning: null,
          templates: prev.templates.map((t) =>
            t.templateId === templateId ? { ...t, useCount: t.useCount + 1 } : t,
          ),
        }));
        return flow;
      } catch (err) {
        setState((prev) => ({
          ...prev,
          cloning: null,
          error: err instanceof Error ? err.message : "Clone failed",
        }));
        return null;
      }
    },
    [],
  );

  const remove = useCallback(
    async (templateId: string): Promise<boolean> => {
      try {
        await deleteTemplate(templateId);
        setState((prev) => ({
          ...prev,
          templates: prev.templates.filter((t) => t.templateId !== templateId),
          total: prev.total - 1,
        }));
        return true;
      } catch (err) {
        setState((prev) => ({
          ...prev,
          error: err instanceof Error ? err.message : "Delete failed",
        }));
        return false;
      }
    },
    [],
  );

  const refresh = useCallback(() => {
    loadTemplates();
  }, [loadTemplates]);

  return {
    ...state,
    filters,
    setFilters,
    clone,
    remove,
    refresh,
  };
}
