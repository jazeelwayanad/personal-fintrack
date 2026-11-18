import { mcpConfig, mcpEnabled, mcpWritesEnabled, readScope, writeScope } from '@/lib/server/mcp-auth';

export function GET() {
  if (!mcpEnabled()) return new Response(null, { status: 404 });
  const { resource, issuer } = mcpConfig();
  return Response.json({
    resource: resource.href,
    authorization_servers: [issuer.href],
    scopes_supported: mcpWritesEnabled() ? [readScope, writeScope] : [readScope],
    bearer_methods_supported: ['header'],
  }, { headers: { 'Cache-Control': 'no-store' } });
}
