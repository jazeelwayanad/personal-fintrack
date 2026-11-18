'use client';

import Link from 'next/link';
import { signOut } from 'next-auth/react';
import { useSyncExternalStore, useState, type FormEvent } from 'react';
import { buttonClass, Field, inputClass } from './finance-forms';

const subscribe = (callback: () => void) => {
  window.addEventListener('hashchange', callback);
  return () => window.removeEventListener('hashchange', callback);
};

export function AccountRecovery() {
  const hash = useSyncExternalStore(subscribe, () => window.location.hash, () => '');
  const params = new URLSearchParams(hash.slice(1));
  const token = params.get('token');
  const kind = params.get('kind');
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const emailChange = !!token && kind === 'email_change';

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    setBusy(true);
    setError('');
    try {
      const result = await fetch('/api/v1/auth/recovery', {
        method: token ? 'PUT' : 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(token ? { token, kind, ...(!emailChange && { password: form.get('password') }) } : { email: form.get('email') }),
      });
      const data = await result.json();
      if (!result.ok) throw new Error(data.error ?? 'Could not complete this request.');
      if (token) window.history.replaceState(null, '', '/recover');
      if (token && !emailChange) await signOut({ redirect: false }).catch(() => {});
      setMessage(token ? (emailChange ? 'Email address verified.' : 'Password updated. Sign in with your new password.') : 'If the address matches a FinTrack account, check its inbox for a recovery link.');
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'Could not complete this request.');
    } finally { setBusy(false); }
  }

  return <main className="mx-auto mt-12 max-w-md px-4">
    <section className="fin-panel space-y-4 p-6">
      <h1 className="text-2xl font-semibold">{emailChange ? 'Verify your email' : 'Account recovery'}</h1>
      {message ? <p role="status">{message}</p> : <form onSubmit={submit} className="space-y-4">
        {!token && <Field label="Account email"><input className={inputClass} name="email" type="email" autoComplete="email" required/></Field>}
        {token && !emailChange && <Field label="New password"><input className={inputClass} name="password" type="password" autoComplete="new-password" minLength={8} required/></Field>}
        <button className={buttonClass} disabled={busy}>{emailChange ? 'Verify email' : token ? 'Save new password' : 'Request recovery link'}</button>
      </form>}
      {error && <p role="alert" className="text-destructive">{error}</p>}
      <Link className="inline-flex min-h-11 items-center text-primary" href="/login">Sign in</Link>
    </section>
  </main>;
}
