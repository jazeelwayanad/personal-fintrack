import { mcpConfig, mcpEnabled, mcpWritesEnabled, readScope, writeScope, paymentsScope } from '@/lib/server/mcp-auth';

import { upiEnabled } from '@/lib/server/upi';

export function GET() {
  if (!mcpEnabled()) return new Response(null, { status: 404 });
  const { resource, issuer } = mcpConfig();
  return Response.json({
    resource: resource.href,
    authorization_servers: [issuer.href],
    scopes_supported: [readScope, ...(mcpWritesEnabled() ? [writeScope] : []), ...(upiEnabled() ? [paymentsScope] : [])],
    bearer_methods_supported: ['header'],
  }, { headers: { 'Cache-Control': 'no-store' } });
}
