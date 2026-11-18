import { cookies } from 'next/headers';
import { NextResponse } from 'next/server';
import { completeIdentityLink, linkCookie, mcpConfig } from '@/lib/server/mcp-auth';
import { requireUser } from '@/lib/server/mobile-auth';

export async function GET(request: Request) {
  const { resource } = mcpConfig();
  const destination = new URL('/settings', resource);
  const proof = (await cookies()).get(linkCookie)?.value;
  try {
    if (!proof) throw new Error('Link expired');
    await completeIdentityLink(await requireUser(request), proof, new URL(request.url).searchParams);
    destination.searchParams.set('mcp', 'linked');
  } catch {
    destination.searchParams.set('mcp', 'link-failed');
  }
  const response = NextResponse.redirect(destination);
  response.cookies.set(linkCookie, '', { httpOnly: true, secure: true, sameSite: 'lax', maxAge: 0, path: '/api/v1/mcp/link/callback' });
  response.headers.set('Cache-Control', 'no-store');
  return response;
}
