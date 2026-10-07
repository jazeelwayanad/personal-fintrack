'use client';
import { useRef, useState } from 'react';
import { MessageSquare, Check, ChevronDown } from 'lucide-react';
import { Dialog, DialogContent, DialogDescription, DialogTitle } from './ui/dialog';
import { Field, inputClass, buttonClass } from './finance-forms';
import { APP_VERSION } from '@/lib/app-info';
export function FeedbackForm() {
  const [open, setOpen] = useState(false), [topic, setTopic] = useState('suggestion');
  const [message, setMessage] = useState(''), [busy, setBusy] = useState(false), [error, setError] = useState(''), [sent, setSent] = useState(false);
  const id = useRef(''), submitting = useRef(false);
  async function submit(event: React.FormEvent) {
    event.preventDefault(); if (submitting.current) return;
    submitting.current = true; setBusy(true); setError('');
    id.current ||= crypto.randomUUID();
    try {
      const response = await fetch('/api/v1/feedback', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id: id.current, topic, message, appVersion: APP_VERSION }) });
      const value = await response.json();
      if (!response.ok) throw new Error(value.details?.join(' ') || value.error || 'Could not send feedback. Please retry.');
      setSent(true); setMessage(''); id.current = '';
    } catch (error) { setError(error instanceof Error ? error.message : 'Could not send feedback. Your message is still here.'); }
    finally { submitting.current = false; setBusy(false); }
  }
  return <><button type="button" onClick={() => { setSent(false); setOpen(true); }} className="flex min-h-12 w-full items-center justify-center gap-2 rounded-full bg-card px-5 py-3 text-sm font-semibold hover:bg-muted"><MessageSquare size={18}/>Give feedback</button>
    <Dialog open={open} onOpenChange={value => { if (!submitting.current) setOpen(value); }}><DialogContent className="max-h-[calc(100dvh-2rem)] overflow-y-auto rounded-3xl gap-5 p-6 sm:max-w-md sm:p-7 [&>button]:top-4 [&>button]:right-4 [&>button]:size-11" showCloseButton={!busy}>
      <DialogTitle className="pr-10 text-xl font-semibold">Give feedback</DialogTitle><DialogDescription>Share an idea or report an issue with Eucodes. Your ledger is not attached.</DialogDescription>
      {sent ? <div role="status" className="space-y-4"><p className="flex items-center gap-2 font-medium"><Check size={20}/>Thank you. Your feedback has been received.</p><button className={buttonClass} onClick={() => setOpen(false)}>Done</button></div> : <form onSubmit={submit} className="space-y-5" aria-busy={busy}>
        <fieldset disabled={busy} className="space-y-5 disabled:opacity-60"><Field label="Topic"><div className="relative"><select className={`${inputClass} min-h-12 appearance-none px-5 pr-12`} value={topic} onChange={e => setTopic(e.target.value)}><option value="suggestion">Suggestion</option><option value="issue">Report an issue</option><option value="other">Other</option></select><ChevronDown size={18} aria-hidden="true" className="pointer-events-none absolute right-4 top-1/2 -translate-y-1/2 text-muted-foreground"/></div></Field>
          <Field label="Your feedback"><textarea className={`${inputClass} min-h-36 resize-y px-5 py-4`} required minLength={10} maxLength={3000} placeholder="What could we improve?" value={message} onChange={e => setMessage(e.target.value)}/></Field><p className="text-xs text-muted-foreground">Please avoid passwords and sensitive financial details. Feedback is saved with your account and app version for developer review and email notification.</p></fieldset>
        {error && <p role="alert" className="rounded-2xl bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}<button disabled={busy} className={`${buttonClass} w-full`}>{busy ? 'Sending…' : 'Send feedback'}</button>
      </form>}
    </DialogContent></Dialog>
  </>;
}
