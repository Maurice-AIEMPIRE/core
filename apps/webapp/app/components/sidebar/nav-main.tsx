import { cn } from "~/lib/utils";
import {
  SidebarGroup,
  SidebarGroupContent,
  SidebarMenu,
  SidebarMenuItem,
} from "../ui/sidebar";
import { useLocation, useNavigate } from "@remix-run/react";
import { Button } from "../ui";

export const NavMain = ({
  items,
}: {
  items: {
    title: string;
    url: string;
    icon?: any;
  }[];
}) => {
  const location = useLocation();
  const navigate = useNavigate();

  return (
    <SidebarGroup>
      <SidebarGroupContent className="flex flex-col gap-2">
        <SidebarMenu className="gap-1">
          {items.map((item) => {
            const isActive = location.pathname.includes(item.url);
            return (
              <SidebarMenuItem key={item.title}>
                <Button
                  isActive={isActive}
                  className={cn(
                    "text-foreground w-full justify-start gap-2 !rounded-lg px-3 transition-all duration-150",
                    isActive
                      ? "!bg-primary/10 !text-primary font-medium shadow-sm"
                      : "hover:bg-grayAlpha-100",
                  )}
                  onClick={() => navigate(item.url)}
                  variant="ghost"
                >
                  {item.icon && (
                    <item.icon
                      size={16}
                      className={cn(
                        "shrink-0 transition-colors",
                        isActive && "text-primary",
                      )}
                    />
                  )}
                  {item.title}
                </Button>
              </SidebarMenuItem>
            );
          })}
        </SidebarMenu>
      </SidebarGroupContent>
    </SidebarGroup>
  );
};
