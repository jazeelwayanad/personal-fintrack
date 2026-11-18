import { api, body } from '@/lib/server/http';
import { connectorSettings, updateGrant } from '@/lib/server/mcp-auth';
import { requireUser } from '@/lib/server/mobile-auth';

export async function GET(req: Request) {
  return api(async () => connectorSettings(await requireUser(req)));
}
export async function POST(req: Request) {
  return api(async () => updateGrant(await requireUser(req), await body(req, 4096)));
}
