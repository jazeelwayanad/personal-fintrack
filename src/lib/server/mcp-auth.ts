import { createHash, randomBytes } from 'node:crypto';
import { createRemoteJWKSet, jwtVerify, SignJWT } from 'jose';
import { z } from 'zod';
import { prisma } from '@/lib/prisma';
import { ApiError } from './api-error';
import { authenticate } from './credentials';
import { secretKey } from './integration-secret';
import { lockLedger } from './sync';
import { upiEnabled } from './upi';

export const readScope = 'ledger:read';
export const writeScope = 'ledger:write';
export const paymentsScope = 'payments:read';
export const mcpEnabled = () => process.env.MCP_READ_ENABLED === 'true';
export const mcpWritesEnabled = () => process.env.MCP_WRITE_ENABLED === 'true';
export const allowedClients = () => (process.env.MCP_ALLOWED_CLIENTS ?? '').split(',').map(value => value.trim()).filter(Boolean);
export const linkCookie = 'fintrack-mcp-link';
const callbackPath = '/api/v1/mcp/link/callback';

export function mcpConfig() {
  if (!mcpEnabled()) throw new ApiError(404, 'MCP is unavailable.');
  const resource = new URL(process.env.MCP_URL ?? '');
  const issuer = new URL(process.env.MCP_ISSUER ?? '');
  if (resource.protocol !== 'https:' || resource.pathname !== '/api/mcp' || resource.search || resource.hash || resource.username || resource.password
    || issuer.protocol !== 'https:' || issuer.pathname !== '/' || issuer.search || issuer.hash || issuer.username || issuer.password) {
    throw new Error('Invalid MCP configuration');
  }
  return { resource, issuer, metadata: new URL('/.well-known/oauth-protected-resource' + resource.pathname, resource) };
}

let jwks: ReturnType<typeof createRemoteJWKSet> | undefined;
let jwksIssuer: string | undefined;
function keys(issuer: URL) {
  if (!jwks || jwksIssuer !== issuer.href) {
    jwks = createRemoteJWKSet(new URL('/.well-known/jwks.json', issuer));
    jwksIssuer = issuer.href;
  }
  return jwks;
}
export async function connectorPrincipal(request: Request) {
  const { issuer, resource } = mcpConfig();
  const token = request.headers.get('authorization')?.match(/^Bearer ([^\s,]+)$/i)?.[1];
  if (!token || token.length > 8192) throw new ApiError(401, 'A connector authorization is required.');
  const payload = await jwtVerify(token, keys(issuer), {
    issuer: issuer.href, audience: resource.href, algorithms: ['RS256'], requiredClaims: ['exp', 'sub'],
  }).then(value => value.payload).catch(() => { throw new ApiError(401, 'Connector authorization is invalid.'); });
  const clientId = typeof payload.azp === 'string' ? payload.azp : payload.client_id;
  if (typeof clientId !== 'string' || !allowedClients().includes(clientId)) throw new ApiError(403, 'This connector is unavailable.');
  const grant = await prisma.mcpGrant.findFirst({
    where: { issuer: issuer.href, subject: payload.sub!, clientId, revokedAt: null },
    orderBy: { createdAt: 'desc' },
  });
  if (!grant) throw new ApiError(403, 'Approve this connector in FinTrack Settings.');
  const scopes = typeof payload.scope === 'string' ? payload.scope.split(' ') : [];
  return { grant, scopes: grant.scopes.filter(scope => scopes.includes(scope)) };
}

function appClient() {
  const { resource, issuer } = mcpConfig();
  const clientId = process.env.MCP_LINK_CLIENT_ID;
  const clientSecret = process.env.MCP_LINK_CLIENT_SECRET;
  if (!clientId || !clientSecret) throw new Error('Missing OIDC client configuration');
  return { issuer, clientId, clientSecret, callback: new URL(callbackPath, resource).href };
}

export async function beginIdentityLink(userId: string, input: unknown, req: Request) {
  const { password } = z.strictObject({ password: z.string().min(8).max(200) }).parse(input);
  const { issuer, clientId, callback } = appClient();
  const owner = await prisma.user.findUniqueOrThrow({ where: { id: userId }, select: { email: true } });
  const auth = await authenticate({ email: owner.email, password }, req);
  if (auth.id !== userId) throw new ApiError(403, 'Confirm your current password.');
  const state = randomBytes(32).toString('base64url');
  const nonce = randomBytes(32).toString('base64url');
  const verifier = randomBytes(32).toString('base64url');
  const proof = await new SignJWT({ state, nonce, verifier, sessionVersion: auth.sessionVersion }).setSubject(userId).setAudience('fintrack-mcp-link')
    .setExpirationTime('10m').setProtectedHeader({ alg: 'HS256' }).sign(secretKey(process.env.MCP_STATE_KEY));
  const url = new URL('/authorize', issuer);
  url.search = new URLSearchParams({
    response_type: 'code', client_id: clientId, redirect_uri: callback, scope: 'openid',
    state, nonce, prompt: 'login', code_challenge_method: 'S256',
    code_challenge: createHash('sha256').update(verifier).digest('base64url'),
  }).toString();
  return { authorizationUrl: url.href, proof };
}

export async function completeIdentityLink(userId: string, proof: string, params: URLSearchParams) {
  const { issuer, clientId, clientSecret, callback } = appClient();
  const code = params.get('code');
  const state = params.get('state');
  const verified = await jwtVerify(proof, secretKey(process.env.MCP_STATE_KEY), { subject: userId, audience: 'fintrack-mcp-link', algorithms: ['HS256'] })
    .catch(() => { throw new ApiError(400, 'Identity link expired. Try again.'); });
  const payload = verified.payload;
  if (!code || !state || state !== payload.state || typeof payload.verifier !== 'string') throw new ApiError(400, 'Invalid identity link.');
  const tokenResponse = await fetch(new URL('/oauth/token', issuer), {
    method: 'POST', redirect: 'error', signal: AbortSignal.timeout(8000),
    body: new URLSearchParams({
      grant_type: 'authorization_code', code, redirect_uri: callback,
      client_id: clientId, client_secret: clientSecret, code_verifier: payload.verifier,
    }),
  });
  if (!tokenResponse.ok) throw new ApiError(400, 'Could not link the connector identity.');
  const token = z.object({ id_token: z.string() }).parse(await tokenResponse.json());
  const identity = (await jwtVerify(token.id_token, keys(issuer), {
    issuer: issuer.href, audience: clientId, algorithms: ['RS256'], requiredClaims: ['exp', 'sub', 'nonce'],
  })).payload;
  if (identity.nonce !== payload.nonce) throw new ApiError(400, 'Invalid identity link.');
  if (Array.isArray(identity.aud) && identity.aud.length > 1 && identity.azp !== clientId) throw new ApiError(400, 'Invalid identity audience.');
  await prisma.$transaction(async tx => {
    await lockLedger(tx, userId);
    const owner = await tx.user.findUniqueOrThrow({ where: { id: userId }, select: { sessionVersion: true } });
    if (owner.sessionVersion !== payload.sessionVersion) throw new ApiError(400, 'Sign in again to link this identity.');
    const assigned = await tx.mcpIdentity.findUnique({ where: { issuer_subject: { issuer: issuer.href, subject: identity.sub! } } });
    if (assigned && assigned.userId !== userId) throw new ApiError(409, 'This identity is linked to another FinTrack account.');
    const previous = await tx.mcpIdentity.findUnique({ where: { userId_issuer: { userId, issuer: issuer.href } } });
    if (previous && previous.subject !== identity.sub) throw new ApiError(409, 'A different identity is already linked.');
    if (!assigned) await tx.mcpIdentity.create({ data: { userId, issuer: issuer.href, subject: identity.sub! } });
  });
}

const grantInput = z.discriminatedUnion('action', [
  z.strictObject({ action: z.literal('grant'), clientId: z.string().min(1).max(200), write: z.boolean(), payments: z.boolean().default(false) }),
  z.strictObject({ action: z.literal('revoke'), grantId: z.uuid() }),
]);
export async function updateGrant(userId: string, input: unknown) {
  const { issuer } = mcpConfig();
  const command = grantInput.parse(input);
  return prisma.$transaction(async tx => {
    await lockLedger(tx, userId);
    if (command.action === 'revoke') {
      await tx.mcpGrant.updateMany({ where: { userId, id: command.grantId, revokedAt: null }, data: { revokedAt: new Date() } });
      return { saved: true };
    }
    if (!allowedClients().includes(command.clientId) || (command.write && !mcpWritesEnabled()) || (command.payments && !upiEnabled())) throw new ApiError(400, 'This connector permission is unavailable.');
    const identity = await tx.mcpIdentity.findUnique({ where: { userId_issuer: { userId, issuer: issuer.href } } });
    if (!identity) throw new ApiError(400, 'Link an identity first.');
    await tx.mcpGrant.updateMany({ where: { userId, issuer: issuer.href, clientId: command.clientId, revokedAt: null }, data: { revokedAt: new Date() } });
    const scopes = [readScope, ...(command.write ? [writeScope] : []), ...(command.payments ? [paymentsScope] : [])];
    await tx.mcpGrant.create({ data: { userId, issuer: issuer.href, subject: identity.subject, clientId: command.clientId, scopes } });
    return { saved: true };
  });
}
export async function connectorSettings(userId: string) {
  const { issuer } = mcpConfig();
  const [identity, grants] = await Promise.all([
    prisma.mcpIdentity.findUnique({ where: { userId_issuer: { userId, issuer: issuer.href } }, select: { subject: true } }),
    prisma.mcpGrant.findMany({ where: { issuer: issuer.href, userId, revokedAt: null }, select: { id: true, clientId: true, scopes: true }, orderBy: { createdAt: 'desc' } }),
  ]);
  return { linked: !!identity, grants, clients: allowedClients(), writesEnabled: mcpWritesEnabled(), paymentsEnabled: upiEnabled() };
}
