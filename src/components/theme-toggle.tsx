"use client"

import * as React from "react"
import { Moon, Sun, Monitor } from "lucide-react"
import { useTheme } from "next-themes"

export function ThemeToggle() {
  const { theme, setTheme } = useTheme()
  const mounted = React.useSyncExternalStore(() => () => {}, () => true, () => false)


  if (!mounted) {
    return (
      <div className="h-11 w-11 rounded-lg bg-secondary animate-pulse" />
    )
  }

  const cycleTheme = () => {
    if (theme === "light") setTheme("dark")
    else if (theme === "dark") setTheme("system")
    else setTheme("light")
  }

  return (
    <button
      onClick={cycleTheme}
      className="relative inline-flex items-center justify-center h-11 w-11 rounded-full bg-secondary/50 hover:bg-secondary transition-all duration-200"
      title={`Current: ${theme}. Click to switch.`}
    >
      {theme === "light" && (
        <Sun className="h-4 w-4 text-muted-foreground transition-all duration-300 animate-in spin-in-90 fade-in" />
      )}
      {theme === "dark" && (
        <Moon className="h-4 w-4 text-muted-foreground transition-all duration-300 animate-in spin-in-90 fade-in" />
      )}
      {theme === "system" && (
        <Monitor className="h-4 w-4 text-muted-foreground transition-all duration-300 animate-in fade-in" />
      )}
      <span className="sr-only">Toggle theme (current: {theme})</span>
    </button>
  )
}
