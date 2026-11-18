import Link from 'next/link';
import { FinanceScreen } from '@/components/finance-screen';
import { SessionControls } from '@/components/session-controls';
import { McpSettings } from '@/components/mcp-settings';

export default async function Page({ searchParams }: { searchParams: Promise<{ mcp?: string }> }) {
  const { mcp } = await searchParams;
  const upi = process.env.UPI_HANDOFF_ENABLED === 'true' && !!process.env.UPI_DATA_KEY;
  const mcpReady = process.env.MCP_READ_ENABLED === 'true' && !!process.env.MCP_ISSUER && !!process.env.MCP_URL
    && !!process.env.MCP_LINK_CLIENT_ID && !!process.env.MCP_LINK_CLIENT_SECRET && !!process.env.MCP_STATE_KEY;
  const integrations = <div className="grid gap-5 md:grid-cols-2">
    <section className="fin-panel space-y-3 p-5 sm:p-6">
      <h2 className="text-base font-semibold">UPI payments</h2>
      <p className="text-sm text-muted-foreground">Scan a payee QR in the Android app, choose a category and purpose, then pay through your installed UPI app.</p>
      {upi ? <Link href="/payments" className="inline-flex min-h-11 items-center rounded-full bg-primary px-5 text-sm font-semibold text-primary-foreground">Payment history and statement matching</Link>
        : <p role="status" className="text-sm">Payments are awaiting server setup.</p>}
    </section>
    {mcpReady ? <McpSettings linkFailed={mcp === 'link-failed'}/> : <section className="fin-panel space-y-3 p-5 sm:p-6">
      <h2 className="text-base font-semibold">AI connectors</h2>
      <p className="text-sm text-muted-foreground">Connect an AI assistant to your synced ledger, with separate permissions for reading, manual entries and payment history.</p>
      <p role="status" className="text-sm">Connection setup is pending. Access will be available once the service is configured.</p>
    </section>}
  </div>;
  return <>
    <FinanceScreen screen="settings" topContent={integrations}/>
    <SessionControls/>
  </>;
}
