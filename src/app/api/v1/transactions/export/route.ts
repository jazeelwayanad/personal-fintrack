import { api } from '@/lib/server/http';
import { requireUser } from '@/lib/server/mobile-auth';
import { pull } from '@/lib/server/sync';
import { number as n, string as s } from '@/lib/finance/model';

function csvField(value: string) {
  const text = /^[\t\r\n]|^\s*[=+@-]/u.test(value) ? "'" + value : value;
  return '"' + text.replaceAll('"', '""') + '"';
}
export async function GET(req: Request) {
  try {
    const user = await requireUser(req);
    const { records } = await pull(user, 0);
    const active = records.filter(record => !record.deleted);
    const labels = new Map(active.filter(row => row.kind === 'category' || row.kind === 'paymentMethod').map(row => [row.id, s(row.data, 'name')]));
    const rows = active.filter(record => record.kind === 'transaction').map(({ data, id }) => [
      id, s(data, 'date'), s(data, 'type'), String(n(data, 'amount')),
      labels.get(s(data, 'categoryId')) ?? '', labels.get(s(data, 'paymentMethodId')) ?? '', s(data, 'description'),
    ].map(csvField).join(','));
    return new Response(['id,date,type,amount_paise,category,payment_method,description', ...rows].join('\r\n') + '\r\n', {
      headers: {
        'Content-Type': 'text/csv; charset=utf-8',
        'Content-Disposition': 'attachment; filename="fintrack-transactions.csv"',
        'Cache-Control': 'no-store',
        'X-Content-Type-Options': 'nosniff',
      },
    });
  } catch (error) {
    return api(async () => { throw error; });
  }
}
