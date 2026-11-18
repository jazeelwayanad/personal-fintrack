import { api, body } from '@/lib/server/http';
import { requireUser } from '@/lib/server/mobile-auth';
import { createUpiAttempt, listUpiAttempts } from '@/lib/server/upi';

export const runtime = 'nodejs';
export async function GET(req: Request) {
  return api(async () => listUpiAttempts(await requireUser(req), new URL(req.url).searchParams));
}
export async function POST(req: Request) {
  return api(async () => createUpiAttempt(await requireUser(req), await body(req, 8192)));
}
