import LoginPage from '@/components/login-page';

export default function Page() {
  return <LoginPage recoveryEnabled={process.env.ACCOUNT_VERIFICATION_ENABLED === 'true'}/>;
}
