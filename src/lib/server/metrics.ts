export async function measure<T>(operation: string, work: () => Promise<T>): Promise<T> {
  if (process.env.FINTRACK_METRICS_ENABLED !== 'true') return work();
  const started = performance.now();
  let outcome = 'failed';
  try {
    const result = await work();
    outcome = 'ok';
    return result;
  } finally {
    console.info('[FinTrack]', { operation, outcome, elapsedMs: Math.round(performance.now() - started) });
  }
}
