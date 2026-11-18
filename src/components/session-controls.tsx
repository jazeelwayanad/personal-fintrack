'use client';

import { signOut } from 'next-auth/react';
import { useState, type FormEvent } from 'react';
import { buttonClass, Field, inputClass } from './finance-forms';
import { useFinance } from './finance-provider';

export function SessionControls() {
  const { pending, store } = useFinance();
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  async function revoke(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy) return;
    const form = event.currentTarget;
    const password = new FormData(form).get('password');
    form.reset();
    setBusy(true);
    setError('');
    try {
      const response = await fetch('/api/v1/account/sessions', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password }),
      });
      if (!response.ok) throw new Error((await response.json()).error ?? 'Could not sign out other devices.');
      store.stop();
      await signOut({ callbackUrl: '/login' });
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'Could not sign out other devices.');
      setBusy(false);
    }
  }

  return <section className="fin-panel mt-6 space-y-3 p-5">
    <h2 className="text-base font-semibold">Device sessions</h2>
    {!open && <button type="button" className="min-h-11 font-semibold text-destructive" onClick={() => setOpen(true)}>Sign out on all devices</button>}
    {open && <form onSubmit={revoke} className="max-w-md space-y-3">
      <p className="text-sm">This signs you out on this device too.{pending ? ' Unsynced edits stay on the device where you made them.' : ''}</p>
      <Field label="Current password"><input className={inputClass} name="password" type="password" autoComplete="current-password" required/></Field>
      <div className="flex flex-wrap gap-2">
        <button className={buttonClass} disabled={busy}>Confirm sign out</button>
        <button type="button" className="min-h-11 px-4" disabled={busy} onClick={() => { setOpen(false); setError(''); }}>Cancel</button>
      </div>
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
    </form>}
  </section>;
}
