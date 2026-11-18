import { notFound } from 'next/navigation';
import { AccountRecovery } from '@/components/account-recovery';

export default function Recover() {
  if (process.env.ACCOUNT_VERIFICATION_ENABLED !== 'true') notFound();
  return <AccountRecovery/>;
}
