import { forwardRef } from "react";
import { cn } from "../../lib/utils";

export const Card = forwardRef(function Card({ className, variant, ...props }, ref) {
  return (
    <section
      ref={ref}
      className={cn("ui-card", variant && `ui-card--${variant}`, className)}
      {...props}
    />
  );
});

export const CardHeader = forwardRef(function CardHeader({ className, ...props }, ref) {
  return <div ref={ref} className={cn("ui-card__header", className)} {...props} />;
});

export const CardTitle = forwardRef(function CardTitle({ className, ...props }, ref) {
  return <h3 ref={ref} className={cn("ui-card__title", className)} {...props} />;
});

export const CardDescription = forwardRef(function CardDescription({ className, ...props }, ref) {
  return <p ref={ref} className={cn("ui-card__description", className)} {...props} />;
});

export const CardAction = forwardRef(function CardAction({ className, ...props }, ref) {
  return <div ref={ref} className={cn("ui-card__action", className)} {...props} />;
});

export const CardContent = forwardRef(function CardContent({ className, ...props }, ref) {
  return <div ref={ref} className={cn("ui-card__content", className)} {...props} />;
});

export const CardFooter = forwardRef(function CardFooter({ className, ...props }, ref) {
  return <div ref={ref} className={cn("ui-card__footer", className)} {...props} />;
});
