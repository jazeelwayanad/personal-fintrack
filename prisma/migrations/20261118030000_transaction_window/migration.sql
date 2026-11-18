CREATE INDEX "FinancialRecord_active_transaction_date_idx"
ON "FinancialRecord" ("userId", ("data"->>'date'))
WHERE NOT "deleted" AND "kind" = 'transaction';
