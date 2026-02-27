import { Button } from "~/components/ui";
import { LoaderCircle } from "lucide-react";
import { ClientOnly } from "remix-utils/client-only";
import { OnboardingSummary } from "./onboarding-summary.client";

interface OnboardingStep2Props {
  summary: string;
  onComplete?: () => void;
  isCompleting?: boolean;
}

export function OnboardingStep2({
  summary,
  onComplete,
  isCompleting,
}: OnboardingStep2Props) {
  return (
    <div className="flex h-[calc(100vh_-_64px)] w-full flex-col items-center justify-center overflow-hidden">
      <div className="flex h-full w-full justify-center overflow-y-auto">
        <div className="flex max-w-3xl flex-col gap-8 pt-10">
          <div className="rounded-lg p-6">
            <ClientOnly
              fallback={
                <div className="flex w-full justify-center">
                  <LoaderCircle className="mr-2 h-4 w-4 animate-spin" />
                </div>
              }
            >
              {() => <OnboardingSummary summary={summary} />}
            </ClientOnly>
          </div>
        </div>
      </div>

      <div className="border-t-1 flex w-full shrink-0 flex-col items-center justify-center space-y-4 border-gray-300">
        <div className="flex w-full max-w-3xl flex-wrap items-center justify-between py-2">
          <h3 className="text-md">
            next step: connect your digital brain to agents
          </h3>

          <div className="flex justify-end">
            <Button
              size="lg"
              variant="secondary"
              onClick={onComplete}
              disabled={isCompleting}
              isLoading={isCompleting}
            >
              connect to agents
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}
