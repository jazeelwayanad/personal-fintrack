import { connection } from 'next/server';
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

export default async function Payments({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  await connection();
  if (!upiEnabled()) notFound();
  const session = await auth();
  if (!session?.user?.id) return <Link href="/login">Sign in to see your payment history</Link>;
  const search = await searchParams;
  const params = new URLSearchParams();
  for (const name of ['cursor', 'from', 'to', 'status', 'evidence']) {
    const value = search[name];
    if (typeof value === 'string' && value) params.set(name, value);
  }
  const nextParams = new URLSearchParams(params);
  const history = await listUpiAttempts(session.user.id, params).catch(() => null);
  if (history?.nextCursor) nextParams.set('cursor', history.nextCursor);
  return <><section className="fin-panel space-y-4 p-5 sm:p-6">
    <h1 className="text-2xl font-semibold">UPI payment history</h1>
    <form action="/payments" className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
      <label className="grid gap-1 text-sm">From<input className="min-h-11 rounded-xl bg-muted px-3" name="from" type="date" defaultValue={params.get('from') ?? ''}/></label>
      <label className="grid gap-1 text-sm">Before<input className="min-h-11 rounded-xl bg-muted px-3" name="to" type="date" defaultValue={params.get('to') ?? ''}/></label>
      <label className="grid gap-1 text-sm">Status<select className="min-h-11 rounded-xl bg-muted px-3" name="status" defaultValue={params.get('status') ?? ''}>
        <option value="">All statuses</option>{Object.entries(statuses).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
      </select></label>
      <label className="grid gap-1 text-sm">Evidence<select className="min-h-11 rounded-xl bg-muted px-3" name="evidence" defaultValue={params.get('evidence') ?? ''}>
        <option value="">All evidence</option><option value="unverified">Unverified</option><option value="manual">Recorded manually</option><option value="statement">Uploaded statement</option>
      </select></label>
      <button className="min-h-11 self-end rounded-full bg-primary px-4 text-primary-foreground">Apply filters</button>
    </form>
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
    {history?.nextCursor && <Link className="inline-flex min-h-11 items-center text-primary" href={'/payments?' + nextParams}>Next page</Link>}
  </section><StatementReview/></>;
}
