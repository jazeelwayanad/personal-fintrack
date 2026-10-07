'use client';

import Link from 'next/link';
import { signOut, useSession } from 'next-auth/react';
import { LogOut, Settings, ShieldCheck, UserRound } from 'lucide-react';
import { useFinance } from '@/components/finance-provider';
import { useConfirm } from '@/components/confirm-dialog';

export default function AccountPage() {
  const { data: session } = useSession();
  const { status, pending, store } = useFinance();
  const ask = useConfirm();

  async function logout() {
    if (pending && !await ask({
      title: 'Sign out?',
      message: 'Your unsynced changes will remain saved on this device.',
      action: 'Sign out',
    })) return;
    store.stop();
    await fetch('/api/v1/devices', {
      method: 'DELETE',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: localStorage.getItem('fintrack-device') ?? '' }),
    }).catch(() => {});
    await signOut({ callbackUrl: '/login' });
  }

  return <div className="flex max-w-2xl min-h-[calc(100dvh-13rem)] flex-col gap-5 pb-20 md:min-h-[calc(100dvh-11rem)] md:pb-0">
    <div>
      <p className="text-xs font-extrabold uppercase tracking-[0.18em] text-[#315845] dark:text-primary">Your FinTrack</p>
      <h1 className="mt-1 text-3xl font-semibold tracking-tight">My account</h1>
    </div>
    <section className="fin-panel flex items-center gap-4 p-6">
      <span className="grid size-16 shrink-0 place-items-center rounded-xl bg-accent text-accent-foreground"><UserRound size={30}/></span>
      <div className="min-w-0">
        <h2 className="truncate text-xl font-bold">{session?.user?.name || 'FinTrack account'}</h2>
        <p className="truncate text-sm text-muted-foreground">{session?.user?.email || ''}</p>
      </div>
    </section>
    <section className="fin-panel p-6">
      <div className="flex items-start gap-3">
        <span className="grid size-10 shrink-0 place-items-center rounded-2xl bg-[#e8f5e6] text-[#315845]"><ShieldCheck size={21}/></span>
        <div><h2 className="font-bold">Your data</h2><p className="mt-1 text-sm text-muted-foreground">{status} · {pending} pending {pending === 1 ? 'change' : 'changes'}</p></div>
      </div>
      <Link href="/settings" className="mt-5 inline-flex items-center gap-2 rounded-xl bg-primary px-5 py-3 text-sm font-semibold text-primary-foreground"><Settings size={17}/>Settings</Link>
    </section>
    <div className="mt-auto pt-5">
      <button onClick={() => void logout()} className="flex w-full items-center justify-center gap-2 rounded-[1.25rem] border border-border bg-white px-5 py-4 text-sm font-bold transition-colors hover:bg-[#f5ffef] dark:bg-card dark:hover:bg-muted"><LogOut size={18}/>Sign out</button>
    </div>
  </div>;
}
