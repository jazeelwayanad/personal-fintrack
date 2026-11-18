import { cookies } from 'next/headers';
import { api, body } from '@/lib/server/http';
import { beginIdentityLink, linkCookie } from '@/lib/server/mcp-auth';
import { requireUser } from '@/lib/server/mobile-auth';

export async function POST(req: Request) {
  return api(async () => {
    const { authorizationUrl, proof } = await beginIdentityLink(await requireUser(req), await body(req, 4096), req);
    (await cookies()).set(linkCookie, proof, { httpOnly: true, secure: true, sameSite: 'lax', maxAge: 600, path: '/api/v1/mcp/link/callback' });
    return { authorizationUrl };
  });
}
