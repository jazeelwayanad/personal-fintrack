"use client"

import { useState } from "react"
import { signIn } from "next-auth/react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { toast } from "sonner"
import { ArrowRight, Wallet, Eye, EyeOff } from "lucide-react"

export default function LoginPage() {
  const router = useRouter()
  const [mode, setMode] = useState<"login" | "register">("login")
  const [loading, setLoading] = useState(false)
  const [showPassword, setShowPassword] = useState(false)
  const [form, setForm] = useState({ name: "", email: "", password: "" })

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
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
          toast.error(data.error || "Registration failed")
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
        toast.error("Invalid email or password")
      } else {
        router.push("/")
        router.refresh()
      }
    } catch {
      toast.error("Something went wrong")
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center p-4">
      {/* Background glow */}
      <div className="fixed inset-0 overflow-hidden pointer-events-none">
        <div className="absolute top-1/4 left-1/2 -translate-x-1/2 w-[600px] h-[600px] rounded-full bg-[#f5ff76]/45 blur-[120px]" />
      </div>

      <div className="w-full max-w-md">
        {/* Logo */}
        <div className="text-center mb-8">
          <div className="w-20 h-20 rounded-[2rem] bg-[#f5ff76] border border-white/80 flex items-center justify-center mx-auto mb-4 shadow-[0_8px_32px_rgba(0,0,0,0.12)]">
            <Wallet className="w-10 h-10 text-[#171b19]" />
          </div>
          <h1 className="text-4xl font-black tracking-tighter text-foreground">
            FinTrack
          </h1>
          <p className="text-muted-foreground text-sm font-medium mt-2">Your personal finance tracker</p>
        </div>

        {/* Card */}
        <div className="fin-panel p-8">
          {/* Tab toggle */}
          <div className="flex bg-[#edf6ee] p-1.5 rounded-2xl gap-1 mb-8 dark:bg-secondary">
            <button
              onClick={() => setMode("login")}
              className={`flex-1 py-2.5 text-sm font-bold rounded-xl transition-all duration-300 ${
                mode === "login"
                  ? "bg-primary text-primary-foreground shadow-md"
                  : "text-muted-foreground hover:text-foreground"
              }`}
            >
              Sign In
            </button>
            <button
              onClick={() => setMode("register")}
              className={`flex-1 py-2.5 text-sm font-bold rounded-xl transition-all duration-300 ${
                mode === "register"
                  ? "bg-primary text-primary-foreground shadow-md"
                  : "text-muted-foreground hover:text-foreground"
              }`}
            >
              Create Account
            </button>
          </div>

          <form onSubmit={handleSubmit} className="space-y-4">
            {mode === "register" && (
              <div className="space-y-2">
                <label className="text-xs font-bold uppercase tracking-widest text-muted-foreground pl-1">Name</label>
                <Input
                  placeholder="Your name"
                  value={form.name}
                  onChange={(e) => setForm({ ...form, name: e.target.value })}
                  className="rounded-2xl h-12 bg-card/40 border-border/40 font-medium focus-visible:ring-primary/30"
                />
              </div>
            )}

            <div className="space-y-2">
              <label className="text-xs font-bold uppercase tracking-widest text-muted-foreground pl-1">Email</label>
              <Input
                type="email"
                required
                placeholder="you@example.com"
                value={form.email}
                onChange={(e) => setForm({ ...form, email: e.target.value })}
                className="rounded-2xl h-12 bg-card/40 border-border/40 font-medium focus-visible:ring-primary/30"
              />
            </div>

            <div className="space-y-2">
              <label className="text-xs font-bold uppercase tracking-widest text-muted-foreground pl-1">Password</label>
              <div className="relative">
                <Input
                  type={showPassword ? "text" : "password"}
                  required
                  minLength={8}
                  placeholder="Min. 8 characters"
                  value={form.password}
                  onChange={(e) => setForm({ ...form, password: e.target.value })}
                  className="rounded-2xl h-12 bg-card/40 border-border/40 font-medium focus-visible:ring-primary/30 pr-12"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-4 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground transition-colors"
                >
                  {showPassword ? <EyeOff className="w-5 h-5" /> : <Eye className="w-5 h-5" />}
                </button>
              </div>
            </div>

            <div className="pt-2">
              <Button
                type="submit"
                disabled={loading}
                className="w-full h-14 text-lg font-black rounded-2xl shadow-lg active:scale-95 transition-all gap-2"
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
