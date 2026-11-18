import { connection } from 'next/server';
import { notFound } from 'next/navigation';
import { AccountRecovery } from '@/components/account-recovery';

export default async function Recover() {
  await connection();
  if (process.env.ACCOUNT_VERIFICATION_ENABLED !== 'true') notFound();
  return <AccountRecovery/>;
}
