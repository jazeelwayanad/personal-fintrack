import NextAuth from "next-auth"
import Credentials from "next-auth/providers/credentials"
import { authenticate, readSessionUser } from "@/lib/server/credentials"
import { ApiError } from "@/lib/server/api-error"
import { ZodError } from "zod"
import authConfig from "./auth.config"

export const { handlers, signIn, signOut, auth } = NextAuth({
  adapter: undefined, // Prisma adapter can be added here if using database session strategy
  session: { strategy: "jwt" },
  ...authConfig,
  callbacks: {
    ...authConfig.callbacks,
    async jwt(args) {
      const token = await authConfig.callbacks!.jwt!(args);
      if (args.user && 'sessionVersion' in args.user) token.sessionVersion = args.user.sessionVersion;
      if (token.userId) {
        const user = await readSessionUser(String(token.userId));
        if (!user || (token.sessionVersion ?? 0) !== user.sessionVersion) return null;
        token.name = user.name;
        token.email = user.email;
      }
      return token;
    },
  },
  providers: [
    Credentials({
      async authorize(credentials, request) {
        try {
          const user = await authenticate(credentials, request)
          return { id: user.id, email: user.email, name: user.name ?? undefined, sessionVersion: user.sessionVersion }
        } catch (error) {
          if (error instanceof ApiError || error instanceof ZodError) return null
          throw error
        }
      },
    }),
  ],
})
