'use client';

import { createContext, useCallback, useContext, useRef, useState } from 'react';
import { Dialog, DialogContent, DialogTitle, DialogDescription } from './ui/dialog';
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

  return <ConfirmContext.Provider value={ask}>
    {children}
    {options && <Dialog open onOpenChange={open => { if (!open) finish(false); }}><DialogContent initialFocus={cancelButton} showCloseButton={false} className="fin-dialog z-[80] sm:max-w-md p-6">
        <div className={`mb-5 grid size-12 place-items-center rounded-2xl ${options.destructive ? 'bg-red-100 text-red-700' : 'bg-[#edf6db] text-[#263b1f]'}`}>
          {options.destructive ? <Trash2 size={23}/> : <AlertTriangle size={23}/>}
        </div>
        <DialogTitle className="text-xl font-semibold tracking-tight">{options.title}</DialogTitle>
        <DialogDescription className="text-sm leading-6 text-muted-foreground">{options.message}</DialogDescription>
        <div className="mt-7 flex gap-3">
          <button ref={cancelButton} className="flex-1 rounded-2xl border border-border bg-card px-4 py-3 text-sm font-semibold" onClick={() => finish(false)}>Cancel</button>
          <button className={`flex-1 rounded-2xl px-4 py-3 text-sm font-semibold ${options.destructive ? 'bg-red-600 text-white' : 'bg-primary text-primary-foreground'}`} onClick={() => finish(true)}>{options.action}</button>
        </div>
      </DialogContent></Dialog>}
  </ConfirmContext.Provider>;
}
