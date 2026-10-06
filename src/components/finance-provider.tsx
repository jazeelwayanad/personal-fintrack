'use client';
import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import { useSession } from 'next-auth/react';
import { useLiveQuery } from 'dexie-react-hooks';
import { FinanceStore } from '@/lib/finance/store';
import { Document } from '@/lib/finance/model';
const Context = createContext<{ store: FinanceStore; records: Document[]; status: string; pending: number } | null>(null);
export function FinanceProvider({ children }: { children: ReactNode }) {
  const { data: session } = useSession();
  return session?.user?.id ? <Account key={session.user.id} id={session.user.id}>{children}</Account> : <p className="p-8">Loading your account…</p>;
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
  if (!records) return <p className="p-8">Opening your ledger…</p>;
  return <Context.Provider value={{ store, records, status: store.status, pending }}>{children}</Context.Provider>;
}
export function useFinance() { const context = useContext(Context); if (!context) throw new Error('FinanceProvider missing'); return context; }
