"use client"
import Image from 'next/image';

import { useRef, useState } from "react"
import { signIn } from "next-auth/react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { toast } from "sonner"
import { ArrowRight, Eye, EyeOff } from "lucide-react"

export default function LoginPage() {
  const router = useRouter()
  const submitting = useRef(false)
  const [error, setError] = useState("")
  const [mode, setMode] = useState<"login" | "register">("login")
  const [loading, setLoading] = useState(false)
  const [showPassword, setShowPassword] = useState(false)
  const [form, setForm] = useState({ name: "", email: "", password: "" })

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (submitting.current) return
    submitting.current = true
    setError("")
    setLoading(true)

    try {
      if (mode === "register") {
        const res = await fetch("/api/auth/register", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(form),
        })
        const data = await res.json()
        if (!res.ok) {
          setError(data.error || "Registration failed")
          setLoading(false)
          return
        }
        toast.success("Account created! Signing you in...")
      }

      const result = await signIn("credentials", {
        email: form.email,
        password: form.password,
        redirect: false,
      })

      if (result?.error) {
        setError("Invalid email or password. Check your details and try again.")
      } else {
        router.push("/")
        router.refresh()
      }
    } catch {
      setError("Could not connect. Your details are still here; please try again.")
    } finally {
      submitting.current = false
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center p-4">
      <div className="w-full max-w-md">
        {/* Logo */}
        <div className="text-center mb-8">
          <div className="w-14 h-14 rounded-2xl bg-accent flex items-center justify-center mx-auto mb-4 ">
            <Image src="/icons/icon-192.png" alt="" width={56} height={56} className="rounded-2xl" priority/>
          </div>
          <h1 className="text-3xl font-semibold tracking-tight text-foreground">
            FinTrack
          </h1>
          <p className="text-muted-foreground text-sm font-medium mt-2">Your personal finance tracker</p>
        </div>

        {/* Card */}
        <div className="fin-panel p-5 sm:p-8">
          {/* Tab toggle */}
          <div className="flex bg-muted p-1.5 rounded-2xl gap-1 mb-8 dark:bg-secondary">
            <button
              disabled={loading}
              aria-pressed={mode === "login"}
              onClick={() => { setMode("login"); setError(""); }}
              className={`flex-1 py-2.5 text-sm font-bold rounded-xl transition-all duration-300 ${
                mode === "login"
                  ? "bg-card text-foreground"
                  : "text-muted-foreground hover:text-foreground"
              }`}
            >
              Sign In
            </button>
            <button
              disabled={loading}
              aria-pressed={mode === "register"}
              onClick={() => { setMode("register"); setError(""); }}
              className={`flex-1 py-2.5 text-sm font-bold rounded-xl transition-all duration-300 ${
                mode === "register"
                  ? "bg-card text-foreground"
                  : "text-muted-foreground hover:text-foreground"
              }`}
            >
              Create Account
            </button>
          </div>

          <form onSubmit={handleSubmit} className="space-y-4">
            {mode === "register" && (
              <div className="space-y-2">
                <label htmlFor="name" className="text-sm font-medium text-foreground">Name</label>
                <Input
                  id="name" autoComplete="name" required
                  placeholder="Your name"
                  value={form.name}
                  onChange={(e) => setForm({ ...form, name: e.target.value })}
                  className="rounded-2xl h-12 bg-muted border-0 font-medium focus-visible:ring-primary/30"
                />
              </div>
            )}

            <div className="space-y-2">
              <label htmlFor="email" className="text-sm font-medium text-foreground">Email</label>
              <Input
                id="email" autoComplete="email"
                type="email"
                required
                placeholder="you@example.com"
                value={form.email}
                onChange={(e) => setForm({ ...form, email: e.target.value })}
                className="rounded-2xl h-12 bg-muted border-0 font-medium focus-visible:ring-primary/30"
              />
            </div>

            <div className="space-y-2">
              <label htmlFor="password" className="text-sm font-medium text-foreground">Password</label>
              <div className="relative">
                <Input
                  id="password" autoComplete={mode === "login" ? "current-password" : "new-password"}
                  type={showPassword ? "text" : "password"}
                  required
                  minLength={8}
                  placeholder="Min. 8 characters"
                  value={form.password}
                  onChange={(e) => setForm({ ...form, password: e.target.value })}
                  className="rounded-2xl h-12 bg-muted border-0 font-medium focus-visible:ring-primary/30 pr-12"
                />
                <button
                  type="button"
                  aria-label={showPassword ? "Hide password" : "Show password"}
                  aria-pressed={showPassword}
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-2 grid size-11 place-items-center top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground transition-colors"
                >
                  {showPassword ? <EyeOff className="w-5 h-5" /> : <Eye className="w-5 h-5" />}
                </button>
              </div>
            </div>

            {error && <p role="alert" className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}
            <div className="pt-2">
              <Button
                type="submit"
                disabled={loading}
                className="w-full h-12 text-sm font-semibold rounded-full gap-2 bg-[#ffe03d] text-[#073b3b] hover:bg-[#f5d532]"
              >
                {loading ? "Please wait..." : mode === "login" ? "Sign In" : "Create Account"}
                {!loading && <ArrowRight className="w-5 h-5" />}
              </Button>
            </div>
          </form>
        </div>
      </div>
    </div>
  )
}
