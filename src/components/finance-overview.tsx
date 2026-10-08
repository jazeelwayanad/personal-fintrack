'use client';

import Image from 'next/image';

import { type ReactNode } from 'react';
import Link from 'next/link';
import { useSession } from 'next-auth/react';
import { ArrowDownLeft, ArrowUpRight, CalendarDays, ChartColumn, ShieldCheck, ChevronDown } from 'lucide-react';
import { rupees, summary } from '@/lib/finance/engine';

type Totals = ReturnType<typeof summary>;
export function FinanceOverview({ totals, period, budgets, payments, activity, spending, add }: {
  totals: Totals; period: string; budgets: ReactNode; payments: ReactNode; activity: ReactNode; spending: ReactNode; add: (type: 'income' | 'expense') => void;
}) {
  const { data: session } = useSession();
  const firstName = session?.user?.name?.trim().split(/\s+/)[0];
  const money = rupees;
  return <>
    <div className="fin-overview-heading"><div><h1>{firstName ? `Hello, ${firstName}.` : 'Welcome back.'}</h1><p className="text-sm text-muted-foreground">Let’s make room for what matters.</p></div></div>
    <div className="fin-overview-grid">
      <div className="fin-overview-column">
        <section className="fin-credit-card" aria-label="Available credit">
          <div className="flex items-center justify-between gap-3"><h2 className="text-sm font-normal">Available credit</h2></div>
          <p className="fin-credit-amount">{money(totals.unallocated)}<span>INR</span></p>
          <p className="fin-credit-definition">After bills, savings & category reserves</p>
          <div className="fin-credit-footer"><span><CalendarDays size={15}/>{period}</span></div>
        </section>
        <div className="fin-quick-actions" aria-label="Quick actions">
          <button onClick={() => add('expense')}><span className="fin-icon-peach"><ArrowUpRight size={20}/></span>Expense</button>
          <button onClick={() => add('income')}><span className="fin-icon-mint"><ArrowDownLeft size={20}/></span>Income</button>
          <Link href="/plans"><span className="fin-icon-yellow"><CalendarDays size={20}/></span>Plans</Link>
          <Link href="/reports"><span className="fin-icon-blue"><ChartColumn size={20}/></span>Reports</Link>
        </div>
        <section className="fin-supporting-totals" aria-label="Balance breakdown">
          {[['Current balance', totals.balance, 'Recorded money to date'], ['Bills reserved', totals.commitments, 'Unpaid scheduled expenses'], ['Protected savings', totals.savings, 'Set aside in preferences']].map(([label, amount, description]) => <div key={label} title={String(description)}><p>{label}</p><strong>{money(Number(amount))}</strong></div>)}
        </section>
        {totals.unallocated < 0 && <p role="status" className="rounded-2xl bg-destructive/10 p-4 text-sm text-destructive">Your commitments exceed recorded money by {money(-totals.unallocated)}. Review your bills and budgets.</p>}
        <section className="fin-panel p-5 sm:p-6"><div className="fin-section-heading"><h2>Next payments</h2><Link href="/plans#schedule">Manage plans</Link></div><p className="fin-section-description">The oldest unpaid payment for each plan, including overdue bills.</p>{payments}</section>
      </div>
      <div className="fin-overview-column">
        <section className="fin-panel p-5 sm:p-6"><div className="fin-section-heading"><h2>Your budgets</h2><span>This cycle</span></div><p className="fin-section-description">Small limits. A little more breathing room.</p>{budgets}</section>
        <section className="fin-panel p-5 sm:p-6"><div className="fin-section-heading"><h2>Recent activity</h2><Link href="/transactions">View all <ArrowUpRight size={14}/></Link></div>{activity}</section>
        <details className="fin-panel fin-spending"><summary><span className="fin-icon-mint"><ShieldCheck size={19}/></span><span><strong>Can I spend this?</strong><small>Check before you checkout.</small></span><ChevronDown size={18}/></summary><div className="px-5 pb-5">{spending}</div></details>
        <p className="fin-overview-note"><Image src="/icons/icon-192.png" alt="" width={18} height={18} className="rounded"/>Thoughtful planning. A calmer month.</p>
      </div>
    </div>
  </>;
}
