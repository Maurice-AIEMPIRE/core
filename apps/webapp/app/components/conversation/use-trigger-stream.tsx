import React, { useEffect, useRef, useState } from "react";
import { EventSource, type ErrorEvent } from "eventsource";

const getTriggerAPIURL = (apiURL?: string) => {
  return (
    (apiURL?.includes("trigger-webapp") ? "http://localhost:8030" : apiURL) ??
    "https://trigger.heysol.ai"
  );
};

export const useTriggerStream = (
  runId: string,
  token: string,
  apiURL?: string,
  afterStreaming?: (finalMessage: string) => void,
) => {
  const baseURL = React.useMemo(() => getTriggerAPIURL(apiURL), [apiURL]);
  const [error, setError] = useState<ErrorEvent | null>(null);
  const [message, setMessage] = useState("");
  const messageRef = useRef("");
  const eventSourceRef = useRef<EventSource | null>(null);

  useEffect(() => {
    const eventSource = new EventSource(
      `${baseURL}/realtime/v1/streams/${runId}/messages`,
      {
        fetch: (input, init) =>
          fetch(input, {
            ...init,
            headers: {
              ...init.headers,
              Authorization: `Bearer ${token}`,
            },
          }),
      },
    );

    eventSourceRef.current = eventSource;

    eventSource.onmessage = (event) => {
      try {
        const eventData = JSON.parse(event.data);

        if (eventData.type.includes("MESSAGE_")) {
          setMessage((prevMessage) => {
            const newMessage = prevMessage + eventData.message;
            messageRef.current = newMessage;
            return newMessage;
          });
        }
      } catch (e) {
        console.error("Failed to parse message:", e);
      }
    };

    eventSource.onerror = (err) => {
      console.error("EventSource failed:", err);
      setError(err);
      eventSource.close();
      if (afterStreaming) {
        afterStreaming(messageRef.current);
      }
    };

    // Cleanup: close EventSource on unmount to prevent memory leak
    return () => {
      eventSource.close();
      eventSourceRef.current = null;
    };
  }, [baseURL, runId, token]);

  return { error, message, actionMessages: [] };
};
