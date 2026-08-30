import { useLayoutEffect } from "react";

export const pageColors = {
  paper: "#fffef9",
  yellow: "#ffd108",
  black: "#050505"
} as const;

export function usePageChrome(color?: string) {
  useLayoutEffect(() => {
    if (!color) return;

    const root = document.documentElement;
    const body = document.body;
    let theme = document.querySelector<HTMLMetaElement>('meta[name="theme-color"]');
    const createdTheme = !theme;
    if (!theme) {
      theme = document.createElement("meta");
      theme.name = "theme-color";
      document.head.append(theme);
    }

    const previousTheme = theme.content;
    const previousRootColor = root.style.backgroundColor;
    const previousBodyColor = body.style.backgroundColor;

    theme.content = color;
    root.style.backgroundColor = color;
    body.style.backgroundColor = color;

    return () => {
      if (createdTheme) theme.remove();
      else theme.content = previousTheme;
      root.style.backgroundColor = previousRootColor;
      body.style.backgroundColor = previousBodyColor;
    };
  }, [color]);
}
