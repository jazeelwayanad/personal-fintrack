import { after } from 'next/server';
import { deliverFeedback } from '@/lib/server/feedback-email';
import { api, body } from '@/lib/server/http';
import { requireUser } from '@/lib/server/mobile-auth';
import { submitFeedback } from '@/lib/server/feedback';
export const runtime = 'nodejs';
export const maxDuration = 30;
export async function POST(req: Request) {
  return api(async () => {
    const userId = await requireUser(req), input = await body(req);
    const result = await submitFeedback(userId, input);
    after(() => deliverFeedback(userId, (input as { id: string }).id));
    return result;
  });
}
