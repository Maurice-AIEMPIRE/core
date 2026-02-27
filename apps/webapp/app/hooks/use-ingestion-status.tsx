import { useEffect, useRef, useState } from "react";
import { useFetcher } from "@remix-run/react";

export interface IngestionQueueItem {
  id: string;
  status: "PENDING" | "PROCESSING" | "COMPLETED" | "FAILED" | "CANCELLED";
  createdAt: string;
  error?: string;
  data: any;
}

export interface IngestionStatusResponse {
  queue: IngestionQueueItem[];
  count: number;
}

export function useIngestionStatus() {
  const fetcher = useFetcher<IngestionStatusResponse>();
  const [isPolling, setIsPolling] = useState(false);
  const intervalRef = useRef<NodeJS.Timeout | null>(null);

  const hasActiveRecords = (data: IngestionStatusResponse | undefined) => {
    if (!data || !data.queue) return false;
    return data.queue.some(item => item.status === "PROCESSING" || item.status === "PENDING");
  };

  const startPolling = () => {
    if (intervalRef.current) return; // Already polling

    const pollIngestionStatus = () => {
      // Pause polling when tab is hidden to save resources
      if (document.visibilityState === "hidden") return;
      if (fetcher.state === "idle") {
        fetcher.load("/api/v1/ingestion-queue/status");
      }
    };

    intervalRef.current = setInterval(pollIngestionStatus, 3000);
    setIsPolling(true);
  };

  const stopPolling = () => {
    if (intervalRef.current) {
      clearInterval(intervalRef.current);
      intervalRef.current = null;
      setIsPolling(false);
    }
  };

  useEffect(() => {
    // Initial load to check if we need to start polling
    if (fetcher.state === "idle" && !fetcher.data) {
      fetcher.load("/api/v1/ingestion-queue/status");
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (fetcher.data) {
      const activeRecords = hasActiveRecords(fetcher.data);

      if (activeRecords && !isPolling) {
        startPolling();
      } else if (!activeRecords && isPolling) {
        stopPolling();
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fetcher.data, isPolling]);

  useEffect(() => {
    return () => {
      stopPolling();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return {
    data: fetcher.data,
    isLoading: fetcher.state === "loading",
    isPolling,
    error: fetcher.data === undefined && fetcher.state === "idle" ? "Error loading ingestion status" : null
  };
}
