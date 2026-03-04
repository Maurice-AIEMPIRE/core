import { Link } from "@remix-run/react";
import {
  Card,
  CardDescription,
  CardHeader,
  CardTitle,
} from "~/components/ui/card";
import { getIcon, type IconType } from "~/components/icon-utils";
import { Badge } from "../ui/badge";
import { OnboardingModal, type ProviderConfig } from "../onboarding";
import { useState } from "react";

interface ProviderCardProps {
  provider: ProviderConfig;
  isConnected: boolean;
}

export function ProviderCard({ provider, isConnected }: ProviderCardProps) {
  const Component = getIcon(provider.icon as IconType);
  const [isOnboardingOpen, setIsOnboardingOpen] = useState(false);

  const handleOnboardingClose = () => {
    setIsOnboardingOpen(false);
  };

  const handleOnboardingComplete = () => {
    window.location.reload();
  };

  return (
    <>
      <Card
        className="card-hover cursor-pointer transition-all hover:border-primary/30"
        onClick={() => {
          setIsOnboardingOpen(true);
        }}
      >
        <CardHeader className="p-4">
          <div className="flex items-center justify-between">
            <div className="mb-2 flex h-8 w-8 items-center justify-center rounded-lg bg-primary/10">
              <Component size={18} className="text-primary" />
            </div>

            {isConnected && (
              <div className="flex w-full items-center justify-end">
                <Badge className="h-6 rounded-full bg-success/10 px-3 text-sm text-success">
                  Connected
                </Badge>
              </div>
            )}
          </div>
          <CardTitle className="text-base">{provider.name}</CardTitle>
          <CardDescription className="line-clamp-2 text-sm">
            {provider.description || `Connect to ${provider.name}`}
          </CardDescription>
        </CardHeader>
      </Card>

      <OnboardingModal
        isOpen={isOnboardingOpen}
        onClose={handleOnboardingClose}
        onComplete={handleOnboardingComplete}
        preselectedProvider={provider.id}
      />
    </>
  );
}
