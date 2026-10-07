'use client';

import Image from 'next/image';

import { usePathname } from 'next/navigation';
import Link from 'next/link';
import { Home, CalendarDays, ArrowLeftRight, ChartColumn, Settings, RefreshCw } from 'lucide-react';
import { FinanceProvider, useFinance } from './finance-provider';
import { ConfirmProvider } from './confirm-dialog';
import { ThemeToggle } from './theme-toggle';
import { APP_VERSION, DEVELOPER_NAME } from '@/lib/app-info';
import { ProfileAvatar } from './profile-avatar';

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
    <header className="relative z-30 fin-header bg-background/95 backdrop-blur-xl">
      <div className="mx-auto flex max-w-6xl items-center justify-between gap-3 px-4 py-3 sm:px-6">
        <Link href="/" className="flex items-center gap-2.5 text-lg font-bold tracking-tight">
          <Image src="/icons/icon-192.png" alt="" width={40} height={40} className="rounded-xl" priority/>
          <span>FinTrack<span className="text-primary">.</span></span>
        </Link>
        <nav className="hidden items-center gap-1 rounded-full bg-white/60 p-1 md:flex dark:bg-card/70" aria-label="Main navigation">
          {tabs.map(tab => <Link key={tab.href} href={tab.href} aria-current={pathname === tab.href ? 'page' : undefined} className={`rounded-full px-3 py-2 text-sm font-semibold transition-colors ${pathname === tab.href ? 'bg-card text-foreground' : 'text-muted-foreground hover:text-foreground'}`}>{tab.label}</Link>)}
        </nav>
        <div className="flex items-center gap-1.5">
          <span role="status" className="sr-only">{status}{pending ? ` · ${pending} pending` : ''}</span>
          <button type="button" aria-label="Sync now" title={`${status}${pending ? ` · ${pending} pending` : ''} · Sync now`} disabled={status === 'Syncing'} onClick={() => void store.sync()} className="relative grid size-11 shrink-0 place-items-center rounded-full hover:bg-card disabled:opacity-60"><RefreshCw size={18} className={status === 'Syncing' ? 'motion-safe:animate-spin' : ''}/></button>
          <ThemeToggle/>
          <div className="relative shrink-0"><Link href="/account" aria-label="My account" title="My account" aria-current={pathname === '/account' ? 'page' : undefined} className={`grid size-11 shrink-0 place-items-center overflow-hidden rounded-full transition-colors ${pathname === '/account' ? 'bg-[#171b19] text-white' : 'bg-white/70 hover:bg-white dark:bg-card'}`}><ProfileAvatar/></Link><span aria-hidden="true" className={`absolute -right-0.5 bottom-0 size-2 rounded-full ring-2 ring-background ${status === 'Synced' ? 'bg-emerald-500' : /could not|failed|unavailable|sign in|conflict/i.test(status) ? 'bg-red-500' : 'bg-amber-500'}`}/></div>
        </div>
      </div>
    </header>

    <main id="main-content" className="fin-main mx-auto max-w-6xl px-4 pb-32 pt-6 sm:px-6 md:pb-14">
      {children}
      <footer className="mt-8 flex flex-wrap justify-center gap-x-2 gap-y-1 text-center text-xs text-muted-foreground"><span>FinTrack v{APP_VERSION}</span><span aria-hidden="true">·</span><span>Developed by {DEVELOPER_NAME}</span></footer>
    </main>

    <nav className="fin-mobile-nav fixed inset-x-3 bottom-2 z-40 flex items-center justify-around rounded-[28px] bg-card/95 px-2 py-2 backdrop-blur-xl md:hidden" aria-label="Mobile navigation">
      {tabs.map(tab => <Link key={tab.href} href={tab.href} aria-current={pathname === tab.href ? 'page' : undefined} className={`fin-dock-link ${pathname === tab.href ? 'fin-dock-active' : ''} flex min-w-0 flex-1 flex-col items-center gap-1 rounded-[22px] py-2 text-center text-[10px] font-medium`}>
        <span className={`grid size-6 place-items-center rounded-full ${pathname === tab.href ? 'text-white' : 'text-muted-foreground'}`}><tab.icon size={19}/></span>
        <span className="truncate">{tab.label}</span>
      </Link>)}
    </nav>
  </div>;
}
