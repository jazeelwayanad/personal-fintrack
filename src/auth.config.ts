import type { NextAuthConfig } from "next-auth"

export default {
  providers: [], // Providers are added in auth.ts
  pages: {
    signIn: "/login",
  },
  callbacks: {
    authorized({ auth, request: { nextUrl } }) {
      const isLoggedIn = !!auth?.user
      const isApiAuthRoute = nextUrl.pathname.startsWith("/api/auth")
      const isPublicRoute = ["/login", "/recover"].includes(nextUrl.pathname)
      const isAuthRoute = ["/login"].includes(nextUrl.pathname)

      if (isApiAuthRoute) return true
      if (isAuthRoute) {
        if (isLoggedIn) return Response.redirect(new URL("/", nextUrl))
        return true
      }
      if (!isLoggedIn && !isPublicRoute) {
        return false 
      }
      return true
    },
    jwt({ token, user }) {
      if (user?.id) token.userId = user.id
      return token
    },
    session({ session, token }) {
      if (token.userId) {
        session.user.id = token.userId as string
      }
      return session
    },
  },
} satisfies NextAuthConfig
