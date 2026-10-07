import { document, type Document } from '../src/lib/finance/model';
export { nextPaymentPerPlan } from '../src/lib/finance/presentation';

// This preview never reads an account, IndexedDB, cookies, or the server.
export const previewToday = '2026-10-07';
export const previewName = 'Alex';
export const sampleRecords: Document[] = [
  document('preferences', 'preferences', { payday: 1, savings: 800000, limitMode: 'warn', notifications: true }),
  ...[
    ['food', 'Food & groceries', 'expense', '#BBDDC4'],
    ['transport', 'Transport', 'expense', '#DEE7F4'],
    ['shopping', 'Shopping', 'expense', '#F5D8C8'],
    ['bills', 'Bills', 'expense', '#F7E9AC'],
    ['salary', 'Salary', 'income', '#BBDDC4'],
  ].map(([id, name, type, color]) => document(id, 'category', { name, type, color, icon: '' })),
  document('bank', 'paymentMethod', { name: 'Bank account', icon: '' }),
  document('upi', 'paymentMethod', { name: 'UPI', icon: '' }),
  document('cash', 'paymentMethod', { name: 'Cash', icon: '' }),
  document('opening', 'adjustment', { amount: 850000, date: '2026-10-01', description: 'Opening balance' }),
  document('salary-plan', 'plan', { name: 'Monthly salary', type: 'income', planType: 'salary', amount: 6800000, categoryId: 'salary', startDate: '2026-10-01', recurrence: 'monthly', reminders: true }),
  document('rent', 'plan', { name: 'Apartment rent', type: 'expense', planType: 'expense', amount: 1200000, categoryId: 'bills', startDate: '2026-10-05', recurrence: 'monthly', reminders: true }),
  document('internet', 'plan', { name: 'Home internet', type: 'expense', planType: 'subscription', amount: 89900, categoryId: 'bills', startDate: '2026-10-07', recurrence: 'monthly', reminders: true }),
  document('streaming', 'plan', { name: 'Netflix', type: 'expense', planType: 'subscription', amount: 64900, categoryId: 'bills', startDate: '2026-10-12', recurrence: 'monthly', reminders: true }),
  document('salary-received', 'transaction', { type: 'income', amount: 6800000, categoryId: 'salary', date: '2026-10-01', description: 'Monthly salary', paymentMethodId: 'bank', occurrenceId: 'salary-plan:2026-10-01' }),
  ...[
    ['groceries-1', 320000, 'food', '2026-10-02', 'Weekly groceries', 'upi'],
    ['shopping-1', 485000, 'shopping', '2026-10-03', 'A few things for home', 'upi'],
    ['transport-1', 72000, 'transport', '2026-10-05', 'Metro & auto rides', 'upi'],
    ['groceries-2', 215000, 'food', '2026-10-06', 'Fresh groceries', 'upi'],
    ['coffee', 18000, 'food', '2026-10-07', 'Morning coffee', 'cash'],
  ].map(([id, amount, categoryId, date, description, paymentMethodId]) => document(String(id), 'transaction', { type: 'expense', amount, categoryId, date, description, paymentMethodId })),
  ...[['food', 700000], ['transport', 250000], ['shopping', 600000]].map(([categoryId, amount]) => document(`budget:${categoryId}`, 'budget', { categoryId, amount })),
];

