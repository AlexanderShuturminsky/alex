import { useState, useCallback, useRef, useEffect } from "react";
import { runFlow, getFlowRun, cancelFlowRun, type FlowRun } from "../api/client";

interface UseFlowExecutionReturn {
  currentRun: FlowRun | null;
  isRunning: boolean;
  error: string | null;
  execute: (flowId: string, triggerData?: Record<string, unknown>) => Promise<void>;
  cancel: () => Promise<void>;
  reset: () => void;
}

const POLL_INTERVAL_MS = 1000;

export function useFlowExecution(): UseFlowExecutionReturn {
  const [currentRun, setCurrentRun] = useState<FlowRun | null>(null);
  const [isRunning, setIsRunning] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const pollTimer = useRef<ReturnType<typeof setInterval> | null>(null);

  // Clean up polling on unmount
  useEffect(() => {
    return () => {
      if (pollTimer.current) clearInterval(pollTimer.current);
    };
  }, []);

  const stopPolling = useCallback(() => {
    if (pollTimer.current) {
      clearInterval(pollTimer.current);
      pollTimer.current = null;
    }
  }, []);

  const startPolling = useCallback(
    (runId: string) => {
      stopPolling();
      pollTimer.current = setInterval(async () => {
        try {
          const run = await getFlowRun(runId);
          setCurrentRun(run);
          if (run.status !== "running" && run.status !== "pending") {
            stopPolling();
            setIsRunning(false);
          }
        } catch (err) {
          stopPolling();
          setIsRunning(false);
          setError(err instanceof Error ? err.message : "Polling failed");
        }
      }, POLL_INTERVAL_MS);
    },
    [stopPolling],
  );

  const execute = useCallback(
    async (flowId: string, triggerData: Record<string, unknown> = {}) => {
      setError(null);
      setIsRunning(true);
      try {
        const run = await runFlow(flowId, triggerData);
        setCurrentRun(run);

        if (run.status === "running" || run.status === "pending") {
          startPolling(run.runId);
        } else {
          setIsRunning(false);
        }
      } catch (err) {
        setIsRunning(false);
        setError(err instanceof Error ? err.message : "Execution failed");
      }
    },
    [startPolling],
  );

  const cancel = useCallback(async () => {
    if (!currentRun) return;
    try {
      const updated = await cancelFlowRun(currentRun.runId);
      setCurrentRun(updated);
      stopPolling();
      setIsRunning(false);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Cancel failed");
    }
  }, [currentRun, stopPolling]);

  const reset = useCallback(() => {
    stopPolling();
    setCurrentRun(null);
    setIsRunning(false);
    setError(null);
  }, [stopPolling]);

  return { currentRun, isRunning, error, execute, cancel, reset };
}
