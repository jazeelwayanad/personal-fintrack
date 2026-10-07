import { ApiError } from './sync';
export function requireFinanceCapability(req: Request) {
  if (process.env.FINANCE_REQUIRE_V2 === 'true' && req.headers.get('X-FinTrack-Finance-Version') !== '2') throw new ApiError(426, 'Update FinTrack to version 1.2.0 or refresh the website to reconnect. Your pending changes are safe on this device.');
}
