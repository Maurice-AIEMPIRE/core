import { useState } from "react";
import { Copy, Check, Loader2, AlertCircle } from "lucide-react";
import { Button } from "../ui";
import { SUGGESTED_INGESTION_PROMPTS } from "./provider-config";

interface IngestionStepProps {
  providerName: string;
  ingestionStatus: "idle" | "waiting" | "processing" | "complete" | "error";
  onStartWaiting: () => void;
  error?: string;
}

export function IngestionStep({
  providerName,
  ingestionStatus,
  onStartWaiting,
  error,
}: IngestionStepProps) {
  const [copiedIndex, setCopiedIndex] = useState<number | null>(null);

  const handleCopy = async (text: string, index: number) => {
    await navigator.clipboard.writeText(text);
    setCopiedIndex(index);
    setTimeout(() => setCopiedIndex(null), 2000);
  };

  return (
    <div className="space-y-6">
      <div>
        <h2 className="mb-2 text-xl font-semibold">
          Let's Store Your First Memory
        </h2>
        <p className="text-muted-foreground text-sm">
          Copy one of these prompts and paste it into {providerName} to create
          your first memory
        </p>
      </div>

      {ingestionStatus === "idle" && (
        <>
          <div className="space-y-3">
            {SUGGESTED_INGESTION_PROMPTS.map((prompt, index) => (
              <div
                key={index}
                className="bg-grayAlpha-100 hover:border-primary/50 group relative rounded-lg border border-gray-300 p-4 transition-colors"
              >
                <p className="pr-10 text-sm">{prompt}</p>
                <button
                  onClick={() => handleCopy(prompt, index)}
                  className="hover:bg-background absolute right-3 top-3 rounded-md p-2 transition-colors"
                  title="Copy to clipboard"
                >
                  {copiedIndex === index ? (
                    <Check className="h-4 w-4 text-green-500" />
                  ) : (
                    <Copy className="text-muted-foreground h-4 w-4" />
                  )}
                </button>
              </div>
            ))}
          </div>

          <div className="flex items-center justify-between rounded-lg border border-blue-500/20 bg-blue-500/10 p-4">
            <div className="flex items-start gap-3">
              <AlertCircle className="mt-0.5 h-5 w-5 text-blue-500" />
              <div className="text-sm">
                <p className="font-medium text-blue-700 dark:text-blue-300">
                  Important
                </p>
                <p className="text-blue-600 dark:text-blue-400">
                  After pasting the prompt in {providerName}, click the button
                  below to wait for ingestion
                </p>
              </div>
            </div>
          </div>

          <div className="flex justify-end">
            <Button onClick={onStartWaiting} size="lg">
              I've Sent the Prompt
            </Button>
          </div>
        </>
      )}

      {(ingestionStatus === "waiting" || ingestionStatus === "processing") && (
        <div className="flex flex-col items-center justify-center space-y-4 py-12">
          <Loader2 className="text-primary h-12 w-12 animate-spin" />
          <div className="space-y-2 text-center">
            <h3 className="text-lg font-medium">
              {ingestionStatus === "waiting"
                ? "Waiting for your first ingestion..."
                : "Processing your memory..."}
            </h3>
            <p className="text-muted-foreground max-w-md text-sm">
              {ingestionStatus === "waiting"
                ? "Make sure you've sent the prompt in your provider app. We're listening for the first memory ingestion."
                : "We're storing your information. This usually takes a few seconds."}
            </p>
          </div>
        </div>
      )}

      {ingestionStatus === "complete" && (
        <div className="flex flex-col items-center justify-center space-y-4 py-12">
          <div className="flex h-16 w-16 items-center justify-center rounded-full bg-green-500/10">
            <Check className="h-8 w-8 text-green-500" />
          </div>
          <div className="space-y-2 text-center">
            <h3 className="text-lg font-medium">Memory stored successfully!</h3>
            <p className="text-muted-foreground text-sm">
              Your first memory has been ingested. Let's verify it worked.
            </p>
          </div>
        </div>
      )}

      {ingestionStatus === "error" && (
        <div className="flex flex-col items-center justify-center space-y-4 py-12">
          <div className="flex h-16 w-16 items-center justify-center rounded-full bg-red-500/10">
            <AlertCircle className="h-8 w-8 text-red-500" />
          </div>
          <div className="space-y-2 text-center">
            <h3 className="text-lg font-medium">Something went wrong</h3>
            <p className="text-muted-foreground max-w-md text-sm">
              {error ||
                "We couldn't detect your memory ingestion. Please try again or check your provider connection."}
            </p>
          </div>
          <Button onClick={onStartWaiting} variant="secondary">
            Try Again
          </Button>
        </div>
      )}
    </div>
  );
}
