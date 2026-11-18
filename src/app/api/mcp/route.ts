import { WebStandardStreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js';
import { ApiError } from '@/lib/server/api-error';
import { rateLimit } from '@/lib/server/credentials';
import { body } from '@/lib/server/http';
import { connectorPrincipal, mcpConfig, mcpEnabled, mcpWritesEnabled, readScope, writeScope, paymentsScope } from '@/lib/server/mcp-auth';
import { financeMcpServer, writeTools } from '@/lib/server/mcp-tools';

export const runtime = 'nodejs';

function challenge(metadata: URL, status: number, scope?: string) {
  const details = scope ? ', error="insufficient_scope", scope="' + scope + '"' : '';
  const authorization = 'Bearer resource_metadata="' + metadata.href + '"' + details;
  return new Response(null, { status, headers: { 'WWW-Authenticate': authorization, 'Cache-Control': 'no-store' } });
}

async function handle(request: Request) {
  if (!mcpEnabled()) return new Response(null, { status: 404 });
  const { resource, metadata } = mcpConfig();
  const origin = request.headers.get('origin');
  if (origin && origin !== resource.origin) return new Response(null, { status: 403 });
  try {
    const principal = await connectorPrincipal(request);
    if (!principal.scopes.includes(readScope)) return challenge(metadata, 403, readScope);
    await rateLimit('mcp:' + principal.grant.id, 120, 60_000);
    if (request.method !== 'POST') return new Response(null, { status: 405, headers: { Allow: 'POST' } });
    const parsedBody = await body(request, 32_768);
    const message = parsedBody as { method?: unknown; params?: { name?: unknown } } | null;
    const name = message?.params?.name;
    const writes = mcpWritesEnabled() && principal.scopes.includes(writeScope);
    if (message?.method === 'tools/call' && name === 'list_upi_attempts' && !principal.scopes.includes(paymentsScope)) return challenge(metadata, 403, paymentsScope);
    if (message?.method === 'tools/call' && typeof name === 'string' && writeTools.has(name) && !writes) return challenge(metadata, 403, writeScope);

    const transport = new WebStandardStreamableHTTPServerTransport({ enableJsonResponse: true, sessionIdGenerator: undefined });
    const server = financeMcpServer(principal.grant, writes, principal.scopes.includes(paymentsScope));
    await server.connect(transport);
    try {
      const response = await transport.handleRequest(request, { parsedBody });
      const headers = new Headers(response.headers);
      headers.set('Cache-Control', 'no-store');
      return new Response(response.body, { status: response.status, headers });
    } finally {
      await server.close();
    }
  } catch (error) {
    if (error instanceof ApiError) {
      if (error.status === 401) return challenge(metadata, 401);
      if (error.status === 403) return new Response(error.message, { status: 403, headers: { 'Cache-Control': 'no-store' } });
      return Response.json({ jsonrpc: '2.0', id: null, error: {
        code: error.status === 400 ? -32700 : -32000, message: error.status === 429 ? 'rate_limited' : error.message,
      } }, { status: error.status, headers: { 'Cache-Control': 'no-store' } });
    }
    return new Response('temporarily_unavailable', { status: 503, headers: { 'Cache-Control': 'no-store' } });
  }
}

export const GET = handle;
export const POST = handle;
export const DELETE = handle;
