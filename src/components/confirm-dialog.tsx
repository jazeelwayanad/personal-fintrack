'use client';

import { createContext, useCallback, useContext, useEffect, useRef, useState } from 'react';
import { AlertTriangle, Trash2 } from 'lucide-react';

type ConfirmOptions = {
  title: string;
  message: string;
  action: string;
  destructive?: boolean;
};

const ConfirmContext = createContext<((options: ConfirmOptions) => Promise<boolean>) | null>(null);

export function useConfirm() {
  const ask = useContext(ConfirmContext);
  if (!ask) throw new Error('ConfirmProvider is missing');
  return ask;
}

export function ConfirmProvider({ children }: { children: React.ReactNode }) {
  const [options, setOptions] = useState<ConfirmOptions | null>(null);
  const resolve = useRef<((accepted: boolean) => void) | null>(null);
  const cancelButton = useRef<HTMLButtonElement>(null);

  const finish = useCallback((accepted: boolean) => {
    resolve.current?.(accepted);
    resolve.current = null;
    setOptions(null);
  }, []);

  const ask = useCallback((next: ConfirmOptions) => new Promise<boolean>(done => {
    resolve.current?.(false);
    resolve.current = done;
    setOptions(next);
  }), []);

  useEffect(() => {
    if (!options) return;
    cancelButton.current?.focus();
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') finish(false);
    };
    document.addEventListener('keydown', onKeyDown);
    return () => document.removeEventListener('keydown', onKeyDown);
  }, [options, finish]);

  return <ConfirmContext.Provider value={ask}>
    {children}
    {options && <div className="fixed inset-0 z-[80] flex items-end justify-center bg-black/45 p-3 sm:items-center" onMouseDown={event => { if (event.target === event.currentTarget) finish(false); }}>
      <div role="alertdialog" aria-modal="true" aria-labelledby="fin-confirm-title" aria-describedby="fin-confirm-message" className="fin-panel w-full max-w-md p-6 sm:p-7">
        <div className={`mb-5 grid size-12 place-items-center rounded-2xl ${options.destructive ? 'bg-red-100 text-red-700' : 'bg-[#edf6db] text-[#263b1f]'}`}>
          {options.destructive ? <Trash2 size={23}/> : <AlertTriangle size={23}/>}
        </div>
        <h2 id="fin-confirm-title" className="text-2xl font-bold tracking-tight">{options.title}</h2>
        <p id="fin-confirm-message" className="mt-2 text-sm leading-6 text-muted-foreground">{options.message}</p>
        <div className="mt-7 flex gap-3">
          <button ref={cancelButton} className="flex-1 rounded-2xl border border-border bg-card px-4 py-3 text-sm font-semibold" onClick={() => finish(false)}>Cancel</button>
          <button className={`flex-1 rounded-2xl px-4 py-3 text-sm font-semibold ${options.destructive ? 'bg-red-600 text-white' : 'bg-primary text-primary-foreground'}`} onClick={() => finish(true)}>{options.action}</button>
        </div>
      </div>
    </div>}
  </ConfirmContext.Provider>;
}
