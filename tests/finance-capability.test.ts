import { afterEach, expect, it, vi } from 'vitest';
import { requireFinanceCapability } from '../src/lib/server/finance-capability';
afterEach(() => vi.unstubAllEnvs());
it('keeps legacy clients compatible until activation', () => {
  vi.stubEnv('FINANCE_REQUIRE_V2', 'false');
  expect(() => requireFinanceCapability(new Request('https://fintrack.eucodes.tech/api/v1/sync'))).not.toThrow();
});
it('requires capability 2 after activation', () => {
  vi.stubEnv('FINANCE_REQUIRE_V2', 'true');
  expect(() => requireFinanceCapability(new Request('https://fintrack.eucodes.tech/api/v1/sync'))).toThrow('pending changes are safe');
  expect(() => requireFinanceCapability(new Request('https://fintrack.eucodes.tech/api/v1/sync', {headers:{'X-FinTrack-Finance-Version':'2'}}))).not.toThrow();
});
