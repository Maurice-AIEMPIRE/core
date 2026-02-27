import { useState } from "react";
import {
  Copy,
  Check,
  AlertCircle,
  ThumbsUp,
  ThumbsDown,
  Loader2,
} from "lucide-react";
import { Button } from "../ui";
import { VERIFICATION_PROMPT } from "./provider-config";

interface VerificationStepProps {
  providerName: string;
  verificationResult?: string;
  isCheckingRecall?: boolean;
  onStartChecking: () => void;
  onComplete: () => void;
}

export function VerificationStep({
  providerName,
  verificationResult,
  isCheckingRecall = false,
  onStartChecking,
  onComplete,
}: VerificationStepProps) {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    await navigator.clipboard.writeText(VERIFICATION_PROMPT);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="space-y-6">
      <div>
        <h2 className="mb-2 text-xl font-semibold">Verify Your Memory</h2>
        <p className="text-muted-foreground text-sm">
          Let's test if your memory is working correctly by asking the AI about
          you
        </p>
      </div>

      {!verificationResult && !isCheckingRecall && (
        <>
          <div className="bg-grayAlpha-100 group relative rounded-lg border border-gray-300 p-4">
            <p className="mb-1 text-sm font-medium">Copy this prompt:</p>
            <p className="pr-10 text-sm">{VERIFICATION_PROMPT}</p>
            <button
              onClick={handleCopy}
              className="hover:bg-background absolute right-3 top-3 rounded-md p-2 transition-colors"
              title="Copy to clipboard"
            >
              {copied ? (
                <Check className="h-4 w-4 text-green-500" />
              ) : (
                <Copy className="text-muted-foreground h-4 w-4" />
              )}
            </button>
          </div>

          <div className="flex items-center gap-3 rounded-lg border border-blue-500/20 bg-blue-500/10 p-4">
            <AlertCircle className="h-5 w-5 shrink-0 text-blue-500" />
            <div className="flex-1 text-sm">
              <p className="text-blue-600 dark:text-blue-400">
                Paste this prompt in {providerName}. Once you ask, click the
                button below to detect the recall.
              </p>
            </div>
          </div>

          <div className="flex justify-end gap-3">
            <Button onClick={onComplete} variant="ghost" size="lg">
              Skip Verification
            </Button>
            <Button onClick={onStartChecking} size="lg" variant="secondary">
              I've Asked the Question
            </Button>
          </div>
        </>
      )}

      {isCheckingRecall && !verificationResult && (
        <div className="flex flex-col items-center justify-center space-y-4 py-12">
          <Loader2 className="text-primary h-12 w-12 animate-spin" />
          <div className="space-y-2 text-center">
            <h3 className="text-lg font-medium">
              Waiting for your recall query...
            </h3>
            <p className="text-muted-foreground max-w-md text-sm">
              Make sure you've asked "{VERIFICATION_PROMPT}" in {providerName}.
              We're listening for the recall.
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
