import { prisma } from '@/lib/prisma';
export function feedbackEmailConfigured() { return Boolean(process.env.RESEND_API_KEY && process.env.FEEDBACK_EMAIL_FROM && process.env.FEEDBACK_EMAIL_TO); }
export async function deliverFeedback(userId: string, id: string) {
  if (!feedbackEmailConfigured()) return;
  const feedback = await prisma.feedback.findUnique({ where: { userId_id: { userId, id } }, include: { user: { select: { name: true, email: true } } } });
  if (!feedback || feedback.emailSentAt || feedback.emailAttempts >= 5) return;
  await prisma.feedback.update({ where: { userId_id: { userId, id } }, data: { emailAttempts: { increment: 1 } } });
  try {
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST', headers: { Authorization: `Bearer ${process.env.RESEND_API_KEY}`, 'Content-Type': 'application/json', 'Idempotency-Key': `feedback-${userId}-${id}` },
      body: JSON.stringify({ from: process.env.FEEDBACK_EMAIL_FROM, to: [process.env.FEEDBACK_EMAIL_TO], reply_to: feedback.user.email, subject: `FinTrack feedback: ${feedback.topic}`, text: `From: ${feedback.user.name || 'FinTrack user'} <${feedback.user.email}>\nVersion: ${feedback.appVersion}\nTopic: ${feedback.topic}\nDate: ${feedback.createdAt.toISOString()}\n\n${feedback.message}` }),
      signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) throw new Error(`Email service returned ${response.status}`);
    await prisma.feedback.update({ where: { userId_id: { userId, id } }, data: { emailSentAt: new Date(), emailError: null } });
  } catch (error) {
    await prisma.feedback.update({ where: { userId_id: { userId, id } }, data: { emailError: error instanceof Error && /^Email service returned \d+$/.test(error.message) ? error.message : 'Email delivery could not be completed.' } });
  }
}
export async function retryFeedbackEmails() {
  if (!feedbackEmailConfigured()) return { feedbackEmailConfigured: false };
  const pending = await prisma.feedback.findMany({ where: { emailSentAt: null, emailAttempts: { lt: 5 } }, orderBy: { createdAt: 'asc' }, take: 10, select: { userId: true, id: true } });
  for (let i = 0; i < pending.length; i += 2) await Promise.all(pending.slice(i, i + 2).map(item => deliverFeedback(item.userId, item.id)));
  return { feedbackEmailConfigured: true, attempted: pending.length };
}
