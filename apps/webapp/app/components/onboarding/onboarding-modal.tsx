import { useState, useRef, useEffect } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "../ui/dialog";
import { type Provider, OnboardingStep } from "./types";
import { ProviderSelectionStep } from "./provider-selection-step";
import { IngestionStep } from "./ingestion-step";
import { VerificationStep } from "./verification-step";
import { PROVIDER_CONFIGS } from "./provider-config";
import { Progress } from "../ui/progress";
import { Button } from "../ui/button";

interface OnboardingModalProps {
  isOpen: boolean;
  onClose: () => void;
  onComplete: () => void;
  preselectedProvider?: Provider;
}

export function OnboardingModal({
  isOpen,
  onClose,
  onComplete,
  preselectedProvider,
}: OnboardingModalProps) {
  const [currentStep, setCurrentStep] = useState<OnboardingStep>(
    OnboardingStep.PROVIDER_SELECTION,
  );
  const [selectedProvider, setSelectedProvider] = useState<
    Provider | undefined
  >(preselectedProvider);
  const [ingestionStatus, setIngestionStatus] = useState<
    "idle" | "waiting" | "processing" | "complete" | "error"
  >("idle");
  const [verificationResult, setVerificationResult] = useState<string>();
  const [isCheckingRecall, setIsCheckingRecall] = useState(false);
  const [error, setError] = useState<string>();
  const abortControllerRef = useRef<AbortController | null>(null);
  const stepTimeoutRef = useRef<ReturnType<typeof setTimeout>>();

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      abortControllerRef.current?.abort();
      if (stepTimeoutRef.current) clearTimeout(stepTimeoutRef.current);
    };
  }, []);

  // Calculate progress
  const getProgress = () => {
    switch (currentStep) {
      case OnboardingStep.PROVIDER_SELECTION:
        return 33;
      case OnboardingStep.FIRST_INGESTION:
        return 66;
      case OnboardingStep.VERIFICATION:
        return 100;
      default:
        return 0;
    }
  };

  // Poll for ingestion status
  const pollIngestion = async () => {
    abortControllerRef.current?.abort();
    const controller = new AbortController();
    abortControllerRef.current = controller;
    setIngestionStatus("waiting");

    try {
      const maxAttempts = 30;
      let attempts = 0;
      const startTime = Date.now();

      const poll = async (): Promise<boolean> => {
        if (controller.signal.aborted) return false;
        if (attempts >= maxAttempts) {
          throw new Error("Ingestion timeout - please try again");
        }

        const response = await fetch("/api/v1/documents?limit=1", {
          signal: controller.signal,
        });
        const data = await response.json();

        if (data.logs && data.logs.length > 0) {
          const latestLog = data.logs[0];
          const logTime = new Date(latestLog.time).getTime();
          if (logTime >= startTime) return true;
        }

        await new Promise((resolve, reject) => {
          const timer = setTimeout(resolve, 2000);
          controller.signal.addEventListener("abort", () => {
            clearTimeout(timer);
            reject(new DOMException("Aborted", "AbortError"));
          });
        });
        attempts++;
        return poll();
      };

      const success = await poll();

      if (success && !controller.signal.aborted) {
        setIngestionStatus("complete");
        stepTimeoutRef.current = setTimeout(() => {
          setCurrentStep(OnboardingStep.VERIFICATION);
        }, 2000);
      }
    } catch (err) {
      if ((err as Error).name === "AbortError") return;
      setError(err instanceof Error ? err.message : "Unknown error occurred");
      setIngestionStatus("error");
    }
  };

  const handleProviderSelect = (provider: Provider) => {
    setSelectedProvider(provider);
  };

  const handleContinueFromProvider = () => {
    setCurrentStep(OnboardingStep.FIRST_INGESTION);
  };

  const handleStartWaiting = () => {
    pollIngestion();
  };

  const handleComplete = () => {
    // Mark onboarding as completed in localStorage
    if (typeof window !== "undefined") {
      localStorage.setItem("onboarding_completed", "true");
    }
    setCurrentStep(OnboardingStep.COMPLETE);
    onComplete();
    onClose();
  };

  const handleSkip = () => {
    // Mark onboarding as completed in localStorage
    if (typeof window !== "undefined") {
      localStorage.setItem("onboarding_completed", "true");
    }
    onComplete();
    onClose();
  };

  // Poll for recall logs to detect verification
  const pollRecallLogs = async () => {
    abortControllerRef.current?.abort();
    const controller = new AbortController();
    abortControllerRef.current = controller;
    setIsCheckingRecall(true);

    try {
      const maxAttempts = 30;
      let attempts = 0;
      const startTime = Date.now();

      const poll = async (): Promise<string | null> => {
        if (controller.signal.aborted) return null;
        if (attempts >= maxAttempts) {
          throw new Error("Verification timeout - please try again");
        }

        const response = await fetch("/api/v1/recall-logs?limit=1", {
          signal: controller.signal,
        });
        const data = await response.json();

        if (data.recallLogs && data.recallLogs.length > 0) {
          const latestRecall = data.recallLogs[0];
          const recallTime = new Date(latestRecall.createdAt).getTime();
          if (recallTime >= startTime) {
            return latestRecall.query || "Recall detected successfully";
          }
        }

        await new Promise((resolve, reject) => {
          const timer = setTimeout(resolve, 2000);
          controller.signal.addEventListener("abort", () => {
            clearTimeout(timer);
            reject(new DOMException("Aborted", "AbortError"));
          });
        });
        attempts++;
        return poll();
      };

      const result = await poll();

      if (result && !controller.signal.aborted) {
        setVerificationResult(result);
        setIsCheckingRecall(false);
      }
    } catch (err) {
      if ((err as Error).name === "AbortError") return;
      setError(err instanceof Error ? err.message : "Unknown error occurred");
      setIsCheckingRecall(false);
    }
  };

  const getStepTitle = () => {
    switch (currentStep) {
      case OnboardingStep.PROVIDER_SELECTION:
        return "Step 1 of 3";
      case OnboardingStep.FIRST_INGESTION:
        return "Step 2 of 3";
      case OnboardingStep.VERIFICATION:
        return "Step 3 of 3";
      default:
        return "";
    }
  };

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className="max-h-[70vh] max-w-3xl overflow-y-auto p-4">
        <DialogHeader>
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <DialogTitle className="text-2xl">Welcome to Core</DialogTitle>
              <Button
                variant="ghost"
                size="sm"
                onClick={handleSkip}
                className="text-muted-foreground hover:text-foreground rounded"
              >
                Skip
              </Button>
            </div>
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <p className="text-muted-foreground text-sm">
                  {getStepTitle()}
                </p>
              </div>
              <Progress
                segments={[{ value: getProgress() }]}
                className="mb-2"
                color="#c15e50"
              />
            </div>
          </div>
        </DialogHeader>

        <div>
          {currentStep === OnboardingStep.PROVIDER_SELECTION && (
            <ProviderSelectionStep
              selectedProvider={selectedProvider}
              onSelectProvider={handleProviderSelect}
              onContinue={handleContinueFromProvider}
            />
          )}

          {currentStep === OnboardingStep.FIRST_INGESTION &&
            selectedProvider && (
              <IngestionStep
                providerName={PROVIDER_CONFIGS[selectedProvider].name}
                ingestionStatus={ingestionStatus}
                onStartWaiting={handleStartWaiting}
                error={error}
              />
            )}

          {currentStep === OnboardingStep.VERIFICATION && selectedProvider && (
            <VerificationStep
              providerName={PROVIDER_CONFIGS[selectedProvider].name}
              verificationResult={verificationResult}
              isCheckingRecall={isCheckingRecall}
              onStartChecking={pollRecallLogs}
              onComplete={handleComplete}
            />
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
