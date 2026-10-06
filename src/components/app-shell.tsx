'use client';
import { usePathname } from 'next/navigation';
import Link from 'next/link';
import { signOut } from 'next-auth/react';
import { Home, CalendarDays, ArrowLeftRight, ChartColumn, Settings, Wallet, LogOut } from 'lucide-react';
import { FinanceProvider, useFinance } from './finance-provider';
import { ThemeToggle } from './theme-toggle';
const tabs = [{ href: '/', label: 'Home', icon: Home }, { href: '/plans', label: 'Plans', icon: CalendarDays }, { href: '/transactions', label: 'Transactions', icon: ArrowLeftRight }, { href: '/reports', label: 'Reports', icon: ChartColumn }, { href: '/settings', label: 'Settings', icon: Settings }];
export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  if (pathname === '/login') return children;
  return <FinanceProvider><Shell>{children}</Shell></FinanceProvider>;
}
function Shell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname(), { status, pending, store } = useFinance();
  return <div className="min-h-screen bg-background text-foreground"><header className="sticky top-0 z-30 border-b bg-background/95 backdrop-blur"><div className="mx-auto flex max-w-6xl items-center justify-between gap-4 px-4 py-4"><Link href="/" className="flex items-center gap-2 text-xl font-bold"><Wallet className="text-primary"/>FinTrack</Link><nav className="hidden gap-6 md:flex">{tabs.map(t => <Link key={t.href} href={t.href} className={pathname === t.href ? 'font-semibold text-primary' : 'text-muted-foreground'}>{t.label}</Link>)}</nav><div className="flex items-center gap-3"><ThemeToggle/><button aria-label="Sign out" onClick={async () => { if (pending && !confirm('You have unsynced changes saved on this device. Sign out anyway?')) return; store.stop(); await fetch('/api/v1/devices', { method: 'DELETE', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id: localStorage.getItem('fintrack-device') ?? '' }) }).catch(() => {}); await signOut({ callbackUrl: '/login' }); }}><LogOut size={18}/></button></div></div></header><div className="mx-auto max-w-6xl px-4 pb-28 pt-6"><div className="mb-5 flex items-center justify-between gap-3 text-xs text-muted-foreground"><span>{status}{pending ? ` · ${pending} pending` : ''}</span><button onClick={() => void store.sync()} className="text-primary">Sync now</button></div>{children}</div><nav className="fixed inset-x-0 bottom-0 z-30 flex justify-around border-t bg-background py-3 pb-safe md:hidden">{tabs.map(t => <Link key={t.href} href={t.href} className={`flex flex-col items-center gap-1 text-[11px] ${pathname === t.href ? 'text-primary' : 'text-muted-foreground'}`}><t.icon size={21}/>{t.label}</Link>)}</nav></div>;
}
