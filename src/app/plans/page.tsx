import { FinanceScreen } from '@/components/finance-screen';

export default async function Page({ searchParams }: { searchParams: Promise<{ occurrence?: string | string[] }> }) {
  const { occurrence } = await searchParams;
  return <FinanceScreen screen="plans" occurrenceId={typeof occurrence === 'string' ? occurrence : undefined}/>;
}
