import Link from 'next/link';
import { notFound } from 'next/navigation';
import { StatementReview } from '@/components/statement-review';
import { auth } from '@/auth';
import { rupees } from '@/lib/finance/engine';
import { listUpiAttempts, upiEnabled } from '@/lib/server/upi';

const statuses: Record<string, string> = {
  ready: 'Prepared',
  awaiting_confirmation: 'Awaiting confirmation',
  launch_failed: 'Could not open a UPI app',
  recorded_manually: 'Recorded manually',
};

export default async function Payments({ searchParams }: { searchParams: Promise<{ cursor?: string }> }) {
  if (!upiEnabled()) notFound();
  const session = await auth();
  if (!session?.user?.id) return <Link href="/login">Sign in to see your payment history</Link>;
  const { cursor } = await searchParams;
  const params = new URLSearchParams();
  if (typeof cursor === 'string') params.set('cursor', cursor);
  const history = await listUpiAttempts(session.user.id, params).catch(() => null);
  return <><section className="fin-panel space-y-4 p-5 sm:p-6">
    <h1 className="text-2xl font-semibold">UPI payment history</h1>
    {!history && <p role="alert">Could not load this page of payment history. <Link className="underline" href="/payments">Start again</Link></p>}
    {history?.items.length === 0 && <p>Payment attempts from Android will appear here.</p>}
    <ul className="space-y-3">
      {history?.items.map(item => <li key={item.attemptId} className="fin-activity-row space-y-1 p-4">
        <div className="flex flex-wrap justify-between gap-2"><strong className="break-words">{item.purpose}</strong><span>{rupees(item.amountPaise)}</span></div>
        <p className="text-sm">{new Date(item.createdAt).toLocaleDateString('en-IN', { timeZone: 'Asia/Kolkata' })} · {statuses[item.status]}</p>
        <p className="text-sm break-all">{item.payeeMasked}</p>
        {item.reportedOutcome && <p className="text-sm">Reported by UPI app: {item.reportedOutcome}</p>}
        <p className="text-sm text-muted-foreground">{item.evidenceStatus === 'statement' ? 'Matched to an uploaded statement' : item.evidenceStatus === 'manual' ? 'Manually recorded expense' : 'No independent payment confirmation'}</p>
        {item.reviewRequired && <p role="status" className="text-sm">The linked expense changed. Review it in Transactions.</p>}
      </li>)}
    </ul>
    {history?.nextCursor && <Link className="inline-flex min-h-11 items-center text-primary" href={'/payments?cursor=' + encodeURIComponent(history.nextCursor)}>Next page</Link>}
  </section><StatementReview/></>;
}
