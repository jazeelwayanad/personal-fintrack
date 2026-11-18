import Link from 'next/link';
import { FinanceScreen } from '@/components/finance-screen';
import { SessionControls } from '@/components/session-controls';
import { McpSettings } from '@/components/mcp-settings';

export default async function Page({ searchParams }: { searchParams: Promise<{ mcp?: string }> }) {
  const { mcp } = await searchParams;
  return <>
    <FinanceScreen screen="settings"/>
    <SessionControls/>
    {process.env.MCP_READ_ENABLED === 'true' && <McpSettings linkFailed={mcp === 'link-failed'}/>}
    {process.env.UPI_HANDOFF_ENABLED === 'true' && <Link className="mt-6 inline-flex min-h-11 items-center text-primary" href="/payments">UPI payment history</Link>}
  </>;
}
