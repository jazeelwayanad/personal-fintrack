'use client';
/* eslint-disable @next/next/no-img-element -- This private photo endpoint needs the signed-in user's cookies. */

import { useCallback, useEffect, useRef, useState } from 'react';
import { signOut, useSession } from 'next-auth/react';
import { ArrowLeft, LogOut, UserRound, Camera, Pencil, LoaderCircle, Trash2 } from 'lucide-react';
import { useFinance } from '@/components/finance-provider';
import { useConfirm } from '@/components/confirm-dialog';
import { Field, inputClass, buttonClass } from '@/components/finance-forms';
import { prepareProfilePhoto } from '@/lib/profile-photo';
import { FeedbackForm } from '@/components/feedback-form';
import { toast } from 'sonner';

type Profile = { name: string; email: string; phone: string; image: string | null; photoUploadEnabled: boolean };
async function profileResponse(response: Response): Promise<Profile> {
  const value = await response.json();
  if (!response.ok) throw new Error(value.details?.join(' ') || value.error || 'Could not update your profile.');
  return value;
}

export default function AccountPage() {
  const { data: session, update } = useSession();
  const { pending, store } = useFinance();
  const ask = useConfirm();

  const [profile, setProfile] = useState<Profile | null>(null);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [photoPreview, setPhotoPreview] = useState<string | null>(null);
  const previewRef = useRef<string | null>(null);
  useEffect(() => () => { if (previewRef.current) URL.revokeObjectURL(previewRef.current); }, []);
  const [photoFailed, setPhotoFailed] = useState(false);
  const [draft, setDraft] = useState({ name: '', email: '', phone: '', currentPassword: '' });
  const submitting = useRef(false);
  const fileInput = useRef<HTMLInputElement>(null);
  const load = useCallback((signal?: AbortSignal) => fetch('/api/v1/account', { cache: 'no-store', signal })
    .then(profileResponse)
    .then(value => { if (!signal?.aborted) { setProfile(value); setPhotoFailed(false); setError(''); } })
    .catch(error => { if (!signal?.aborted) setError(error instanceof Error ? error.message : 'Could not load your profile.'); })
    .finally(() => { if (!signal?.aborted) setLoading(false); }), []);
  useEffect(() => { const controller = new AbortController(); void load(controller.signal); return () => controller.abort(); }, [load]);
  function startEdit() {
    if (!profile) return;
    setDraft({ name: profile.name, email: profile.email, phone: profile.phone, currentPassword: '' }); setError(''); setEditing(true);
  }
  function cancelEdit() { setEditing(false); setError(''); setDraft({ name: '', email: '', phone: '', currentPassword: '' }); }
  async function save(event: React.FormEvent) {
    event.preventDefault(); if (submitting.current) return;
    submitting.current = true; setBusy(true); setError('');
    try {
      const saved = await profileResponse(await fetch('/api/v1/account', { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(draft) }));
      setProfile(saved); setEditing(false); setDraft({ name: '', email: '', phone: '', currentPassword: '' });
      window.dispatchEvent(new Event('fintrack-profile-updated'));
      await update().catch(() => {}); toast.success('Account details updated');
    } catch (error) { setError(error instanceof Error ? error.message : 'Could not save. Your entries are still here.'); }
    finally { submitting.current = false; setBusy(false); }
  }
  async function changePhoto(file?: File, remove = false) {
    if ((!file && !remove) || submitting.current) return;
    submitting.current = true; setBusy(true); setError('');
    try {
      const photo = file ? await prepareProfilePhoto(file) : null;
      const saved = await profileResponse(await fetch('/api/v1/account/photo', remove ? { method: 'DELETE' } : { method: 'POST', headers: { 'Content-Type': 'image/jpeg' }, body: photo }));
      if (previewRef.current) URL.revokeObjectURL(previewRef.current);
      previewRef.current = photo ? URL.createObjectURL(photo) : null; setPhotoPreview(previewRef.current);
      setProfile(saved); setPhotoFailed(false); toast.success(remove ? 'Profile photo removed' : 'Profile photo updated');
      window.dispatchEvent(new Event('fintrack-profile-updated'));
    } catch (error) { setError(error instanceof Error ? error.message : 'Could not upload your photo. Please retry.'); }
    finally { submitting.current = false; setBusy(false); if (fileInput.current) fileInput.current.value = ''; }
  }

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

  return <div className="mx-auto flex w-full max-w-2xl min-h-[calc(100dvh-13rem)] flex-col gap-5 pb-20 md:min-h-[calc(100dvh-11rem)] md:pb-0">
    <div className="relative flex min-h-11 items-center justify-center">
      {editing && <button type="button" aria-label="Back to account" disabled={busy} onClick={cancelEdit} className="absolute left-0 grid size-11 place-items-center rounded-full hover:bg-card"><ArrowLeft size={24}/></button>}
      <h1 className="text-2xl font-semibold tracking-tight">{editing ? 'Edit profile' : 'My account'}</h1>
    </div>
    <section className={editing ? 'px-1 py-4 sm:px-6' : 'fin-panel p-5 sm:p-6'} aria-busy={loading || busy}>
      <input ref={fileInput} type="file" accept="image/jpeg,image/png,image/webp" aria-label="Choose profile photo" className="hidden" onChange={event => void changePhoto(event.target.files?.[0])}/>
      <div className="flex flex-col items-center gap-4 text-center">
        <div className="relative mb-2">
          <span className="grid size-32 place-items-center overflow-hidden rounded-full bg-accent text-accent-foreground">
            {profile?.image && !photoFailed ? <img onError={() => setPhotoFailed(true)} src={photoPreview || profile.image} alt="Your profile photo" className="size-full object-cover"/> : <UserRound size={48}/>}
          </span>
          {!editing ? <button type="button" aria-label="Edit details" title="Edit details" disabled={busy || loading || !profile} onClick={startEdit} className="absolute -right-1 bottom-0 grid size-11 place-items-center rounded-full bg-white text-foreground shadow-sm dark:bg-card"><Pencil size={20}/></button> : <details className="absolute -right-1 bottom-0 text-left">
            <summary aria-label="Edit profile photo" title="Edit profile photo" className="grid size-11 cursor-pointer list-none place-items-center rounded-full bg-white text-foreground shadow-sm dark:bg-card [&::-webkit-details-marker]:hidden"><Pencil size={20}/></summary>
            <div role="group" aria-label="Photo actions" className="absolute right-0 z-10 mt-2 w-44 rounded-2xl bg-card p-2 shadow-lg">
              <button type="button" disabled={busy || loading || !profile?.photoUploadEnabled} className="flex min-h-11 w-full items-center gap-2 rounded-xl px-3 text-sm hover:bg-muted disabled:opacity-50" onClick={() => fileInput.current?.click()}>{busy ? <LoaderCircle size={18} className="motion-safe:animate-spin"/> : <Camera size={18}/>}Change photo</button>
              {profile?.image && <button type="button" disabled={busy} className="flex min-h-11 w-full items-center gap-2 rounded-xl px-3 text-sm text-destructive hover:bg-destructive/10 disabled:opacity-50" onClick={() => void changePhoto(undefined, true)}><Trash2 size={18}/>Remove photo</button>}
            </div>
          </details>}
        </div>
        {!editing && <div className="min-w-0 max-w-full"><h2 className="break-words text-xl font-semibold">{profile?.name || session?.user?.name || 'Your profile'}</h2><p className="mt-1 break-all text-sm text-muted-foreground">{profile?.email || session?.user?.email || ''}</p></div>}
      </div>
      {profile && !profile.photoUploadEnabled && <p className="mt-2 text-xs text-muted-foreground">Photo uploads will be available once Cloudinary is configured.</p>}
      {photoFailed && <p role="status" className="mt-2 text-xs text-muted-foreground">Your photo could not be loaded. <button type="button" className="underline" onClick={() => setPhotoFailed(false)}>Try again</button></p>}
      {loading && <p role="status" className="mt-5 text-sm text-muted-foreground">Loading account details…</p>}
      {error && !editing && <div role="alert" className="mt-4 rounded-2xl bg-destructive/10 p-3 text-sm text-destructive">{error}{!profile && <button type="button" className="ml-2 underline" onClick={() => { setLoading(true); setError(''); void load(); }}>Try again</button>}</div>}
      {profile && !editing && <dl className="mt-6 grid gap-5 text-sm">
        <div><dt className="text-xs text-muted-foreground">Name</dt><dd className="mt-1 break-words font-medium">{profile.name || 'Not added'}</dd></div>
        <div><dt className="text-xs text-muted-foreground">Email</dt><dd className="mt-1 break-all font-medium">{profile.email}</dd></div>
        <div><dt className="text-xs text-muted-foreground">Phone</dt><dd className="mt-1 break-words font-medium">{profile.phone || 'Not added'}</dd></div>
      </dl>}
      {editing && <form onSubmit={save} className="mt-6 space-y-4" aria-busy={busy}>
        <fieldset disabled={busy} className="space-y-4 disabled:opacity-60">
          <Field label="Name"><input className={`${inputClass} min-h-14 bg-white px-5 text-base dark:bg-card`} autoComplete="name" required maxLength={120} value={draft.name} onChange={event => setDraft({ ...draft, name: event.target.value })}/></Field>
          <Field label="Email"><input className={`${inputClass} min-h-14 bg-white px-5 text-base dark:bg-card`} type="email" autoComplete="email" required maxLength={254} value={draft.email} onChange={event => setDraft({ ...draft, email: event.target.value })}/></Field>
          <Field label="Phone (optional)"><input className={`${inputClass} min-h-14 bg-white px-5 text-base dark:bg-card`} type="tel" autoComplete="tel" maxLength={30} placeholder="Include your country code" value={draft.phone} onChange={event => setDraft({ ...draft, phone: event.target.value })}/></Field>
          {draft.email.trim().toLowerCase() !== profile?.email && <><Field label="Current password"><input className={`${inputClass} min-h-14 bg-white px-5 text-base dark:bg-card`} type="password" autoComplete="current-password" required maxLength={200} value={draft.currentPassword} onChange={event => setDraft({ ...draft, currentPassword: event.target.value })}/></Field><p className="text-xs text-muted-foreground">Confirm your password to change the email you use to sign in.</p></>}
        </fieldset>
        {error && <p role="alert" className="rounded-2xl bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}
        <div className="flex flex-wrap gap-3"><button className={buttonClass} disabled={busy}>{busy ? 'Saving…' : 'Save changes'}</button><button type="button" className="rounded-full bg-muted px-5 py-3 text-sm" disabled={busy} onClick={cancelEdit}>Cancel</button></div>
      </form>}
    </section>
    <div className="mt-auto space-y-3 pt-5">
      <FeedbackForm/>
      <button disabled={busy} onClick={() => void logout()} className="flex w-full items-center justify-center gap-2 rounded-full bg-[#fce8e6] px-5 py-4 text-sm font-bold text-[#9c3030] transition-colors hover:bg-[#f8d9d6] dark:bg-[#482829] dark:text-[#ffc5bf] dark:hover:bg-[#593031]"><LogOut size={18}/>Sign out</button>
    </div>
  </div>;
}
