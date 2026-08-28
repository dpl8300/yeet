import { forwardRef, type ButtonHTMLAttributes } from "react";
import { cn } from "../../lib/utils";

export const Button = forwardRef<HTMLButtonElement, ButtonHTMLAttributes<HTMLButtonElement> & { variant?: "primary" | "secondary" | "ghost"; size?: "default" | "icon" }>(
  ({ className, variant = "primary", size = "default", ...props }, ref) => (
    <button ref={ref} className={cn("button", `button-${variant}`, size === "icon" && "button-icon", className)} {...props} />
  )
);
Button.displayName = "Button";
