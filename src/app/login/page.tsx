import { connection } from 'next/server';
import LoginPage from '@/components/login-page';

export default async function Page() {
  await connection();
  return <LoginPage recoveryEnabled={process.env.ACCOUNT_VERIFICATION_ENABLED === 'true'}/>;
}
