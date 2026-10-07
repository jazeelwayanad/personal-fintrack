'use client';

import { usePathname } from 'next/navigation';
import Link from 'next/link';
import { Home, CalendarDays, ArrowLeftRight, ChartColumn, Settings, Wallet, UserRound, RefreshCw } from 'lucide-react';
import { FinanceProvider, useFinance } from './finance-provider';
import { ConfirmProvider } from './confirm-dialog';
import { ThemeToggle } from './theme-toggle';

const tabs = [
  { href: '/', label: 'Home', icon: Home },
  { href: '/plans', label: 'Plans', icon: CalendarDays },
  { href: '/transactions', label: 'Activity', icon: ArrowLeftRight },
  { href: '/reports', label: 'Reports', icon: ChartColumn },
  { href: '/settings', label: 'Settings', icon: Settings },
];

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  if (pathname === '/login') return children;
  return <FinanceProvider><ConfirmProvider><Shell>{children}</Shell></ConfirmProvider></FinanceProvider>;
}

function Shell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const { status, pending, store } = useFinance();

  return <div className="min-h-screen text-foreground">
    <a href="#main-content" className="sr-only focus:not-sr-only focus:fixed focus:top-2 focus:left-2 focus:z-50 focus:rounded-lg focus:bg-card focus:p-3">Skip to content</a>
    <header className="sticky top-0 z-30 border-b border-border bg-card/95 backdrop-blur-xl">
      <div className="mx-auto flex max-w-6xl items-center justify-between gap-3 px-4 py-3 sm:px-6">
        <Link href="/" className="flex items-center gap-2.5 text-lg font-bold tracking-tight">
          <span className="grid size-10 place-items-center rounded-xl bg-accent text-accent-foreground"><Wallet size={21}/></span>
          FinTrack
        </Link>
        <nav className="hidden items-center gap-1 rounded-full bg-white/60 p-1 md:flex dark:bg-card/70" aria-label="Main navigation">
          {tabs.map(tab => <Link key={tab.href} href={tab.href} aria-current={pathname === tab.href ? 'page' : undefined} className={`rounded-full px-4 py-2 text-sm font-semibold transition-colors ${pathname === tab.href ? 'bg-primary text-primary-foreground' : 'text-muted-foreground hover:text-foreground'}`}>{tab.label}</Link>)}
        </nav>
        <div className="flex items-center gap-1.5">
          <ThemeToggle/>
          <Link href="/account" aria-label="My account" title="My account" aria-current={pathname === '/account' ? 'page' : undefined} className={`grid size-11 place-items-center rounded-full transition-colors ${pathname === '/account' ? 'bg-[#171b19] text-white' : 'bg-white/70 hover:bg-white dark:bg-card'}`}><UserRound size={18}/></Link>
        </div>
      </div>
    </header>

    <main id="main-content" className="fin-main mx-auto max-w-6xl px-4 pb-32 pt-6 sm:px-6 md:pb-14">
      <div className="mb-5 flex flex-wrap items-center justify-between gap-2 text-xs">
        <span role="status" className="rounded-full bg-white/75 px-3 py-1.5 font-medium text-muted-foreground dark:bg-card">
          <span className={`mr-2 inline-block size-2 rounded-full ${status === 'Synced' ? 'bg-emerald-500' : 'bg-amber-500'}`}/>
          {status}{pending ? ` · ${pending} pending` : ''}
        </span>
        <button onClick={() => void store.sync()} className="inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 font-semibold hover:bg-white/60"><RefreshCw size={14}/>Sync now</button>
      </div>
      {children}
    </main>

    <nav className="fin-mobile-nav fixed inset-x-0 bottom-0 z-40 flex items-center justify-around border-t border-border bg-card/95 px-2 pt-2 backdrop-blur-xl md:hidden" aria-label="Mobile navigation">
      {tabs.map(tab => <Link key={tab.href} href={tab.href} aria-current={pathname === tab.href ? 'page' : undefined} className="flex min-w-0 flex-1 flex-col items-center gap-1 py-1 text-center text-[11px] font-semibold">
        <span className={`grid size-11 place-items-center rounded-full ${pathname === tab.href ? 'bg-[#171b19] text-white dark:bg-[#e4f69a] dark:text-[#14221c]' : 'text-muted-foreground'}`}><tab.icon size={19}/></span>
        <span className="truncate">{tab.label}</span>
      </Link>)}
    </nav>
  </div>;
}
