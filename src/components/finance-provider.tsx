'use client';
import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import Link from 'next/link';
import { signOut, useSession } from 'next-auth/react';
import { useLiveQuery } from 'dexie-react-hooks';
import { FinanceStore } from '@/lib/finance/store';
import { Document } from '@/lib/finance/model';
const Context = createContext<{ store: FinanceStore; records: Document[]; status: string; pending: number } | null>(null);
function LedgerLoading({ children }: { children: ReactNode }) {
  return <div role="status" className="mx-auto max-w-6xl space-y-5 px-4 py-12"><p className="text-sm font-medium text-muted-foreground">{children}</p><div aria-hidden="true" className="grid grid-cols-2 gap-4 motion-safe:animate-pulse"><div className="h-36 rounded-xl bg-muted"/><div className="h-36 rounded-xl bg-muted"/><div className="col-span-2 h-60 rounded-xl bg-muted"/></div></div>;
}
export function FinanceProvider({ children }: { children: ReactNode }) {
  const { data: session, status } = useSession();
  if (status === 'unauthenticated') return <div className="mx-auto max-w-md p-8"><h1 className="text-xl font-semibold">Sign in to open your ledger</h1><p className="my-3 text-sm text-muted-foreground">Your session has ended. Sign in again to continue.</p><Link className="inline-flex min-h-11 items-center font-semibold text-primary" href="/login">Go to sign in</Link></div>;
  return session?.user?.id ? <Account key={session.user.id} id={session.user.id}>{children}</Account> : <LedgerLoading>Loading your account…</LedgerLoading>;
}
function Account({ id, children }: { id: string; children: ReactNode }) {
  const [store] = useState(() => new FinanceStore(id));
  const [, refresh] = useState(0);
  const records = useLiveQuery(() => store.db.documents.toArray(), [store]);
  const pending = useLiveQuery(() => store.db.pending.count(), [store]) ?? 0;
  useEffect(() => {
    const update = () => { void store.sync(); };
    const unlisten = store.listen(() => refresh(v => v + 1));
    update();
    window.addEventListener('online', update); window.addEventListener('focus', update);
    const timer = setInterval(update, 30000);
    return () => { unlisten(); clearInterval(timer); window.removeEventListener('online', update); window.removeEventListener('focus', update); };
  }, [store]);
  if (!records) return <LedgerLoading>Opening your ledger…</LedgerLoading>;
  return <Context.Provider value={{ store, records, status: store.status, pending }}>
    {store.status === 'Please sign in again.' && <div role="alert" className="mb-5 rounded-3xl bg-card p-5 text-sm"><p className="font-semibold">Sign in again to reconnect your ledger</p><p className="mt-1 text-muted-foreground">Your saved entries remain on this device.</p><button type="button" className="mt-3 min-h-11 rounded-full bg-primary px-5 font-semibold text-primary-foreground" onClick={() => { store.stop(); void signOut({ callbackUrl: '/login' }); }}>Sign in again</button></div>}
    {children}
  </Context.Provider>;
}
export function useFinance() { const context = useContext(Context); if (!context) throw new Error('FinanceProvider missing'); return context; }
