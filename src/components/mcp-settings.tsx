'use client';

import { useEffect, useState, type FormEvent } from 'react';
import { buttonClass, Field, inputClass } from './finance-forms';

type Settings = {
  linked: boolean;
  writesEnabled: boolean;
  clients: string[];
  grants: { id: string; clientId: string; scopes: string[] }[];
};
type Command = { action: 'grant'; clientId: string; write: boolean } | { action: 'revoke'; grantId: string };

async function settingsRequest(path: string, payload?: object) {
  const response = await fetch('/api/v1/mcp' + path, payload && {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload),
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error ?? 'Could not load connector settings.');
  return data;
}

export function McpSettings({ linkFailed }: { linkFailed: boolean }) {
  const [settings, setSettings] = useState<Settings>();
  const [error, setError] = useState(linkFailed ? 'Could not link the identity. Try again.' : '');
  const [busy, setBusy] = useState(false);
  const [client, setClient] = useState('');
  const [write, setWrite] = useState(false);
  useEffect(() => {
    let active = true;
    settingsRequest('').then(data => { if (active) setSettings(data); }).catch(error => { if (active) setError(error.message); });
    return () => { active = false; };
  }, []);

  async function link(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = event.currentTarget;
    const password = new FormData(form).get('password');
    form.reset();
    await run(async () => {
      const { authorizationUrl } = await settingsRequest('/link', { password });
      window.location.assign(authorizationUrl);
    });
  }

  async function run(operation: () => Promise<void>) {
    setBusy(true);
    setError('');
    try { await operation(); }
    catch (error) { setError(error instanceof Error ? error.message : 'Could not update connector settings.'); }
    finally { setBusy(false); }
  }

  function change(command: Command) {
    return run(async () => {
      await settingsRequest('', command);
      setSettings(await settingsRequest(''));
      setWrite(false);
    });
  }

  return <section className="fin-panel mt-6 space-y-4 p-5">
    <h2 className="text-base font-semibold">AI connectors</h2>
    {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
    {!settings && !error && <p role="status">Loading connector permissions…</p>}
    {settings && !settings.linked && <form onSubmit={link} className="max-w-md space-y-3">
      <Field label="Current password"><input name="password" type="password" autoComplete="current-password" className={inputClass} required/></Field>
      <button className={buttonClass} disabled={busy}>Link connector identity</button>
    </form>}
    {settings?.linked && <>
      <p className="text-sm">Connectors can use data that has synced to FinTrack.</p>
      <form className="max-w-md space-y-3" onSubmit={event => { event.preventDefault(); void change({ action: 'grant', clientId: client, write }); }}>
        <Field label="Connector"><select className={inputClass} value={client} onChange={event => setClient(event.target.value)} required>
          <option value="">Choose a connector</option>
          {settings.clients.map(id => <option key={id} value={id}>{id}</option>)}
        </select></Field>
        {settings.writesEnabled && <label className="flex items-start gap-2 text-sm"><input type="checkbox" checked={write} onChange={event => setWrite(event.target.checked)}/>Allow this connector to record and reclassify manual ledger entries.</label>}
        <button className={buttonClass} disabled={busy || !client}>Save connector access</button>
      </form>
      <ul className="space-y-2">
        {settings.grants.map(grant => <li key={grant.id} className="flex flex-wrap items-center justify-between gap-2 border-t py-2 text-sm">
          <span className="break-all">{grant.clientId} · {grant.scopes.includes('ledger:write') ? 'Read and write' : 'Read only'}</span>
          <button type="button" className="min-h-11 px-3 text-destructive" disabled={busy} onClick={() => void change({ action: 'revoke', grantId: grant.id })}>Revoke access</button>
        </li>)}
      </ul>
    </>}
  </section>;
}
