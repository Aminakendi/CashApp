# Walkthrough: Budget Notifications

The budget notification system is now fully implemented and active! 

Here is a summary of the new logic and how it handles the edge cases we discussed:

## 1. Interceptor Design (Single Source of Truth)
Instead of copying notification code everywhere, we added a centralized `checkBudgetThresholds` helper in the database (`AnalyticsDao`).
This helper is now actively triggered whenever a transaction is inserted or updated via:
- **SMS Sync** (`processSingleSms`)
- **Manual Entry** (`ManualEntryScreen`)
- **Background Reprocessing**
- **Retroactive Recategorization** (in `home_tab.dart`)

## 2. Notification DB State (Race & Dedup Safety)
We added a new `BudgetNotifications` table to the database.
- It tracks the `categoryId`, `yearMonth`, and the `threshold` (80 or 100).
- **Safe Concurrency**: The table has a compound `UNIQUE` constraint on those three columns. This guarantees that even if a manual entry and an SMS sync push a category over 80% at the exact same millisecond, the database structurally prevents duplicate insertions, meaning the local push notification will only fire exactly once!
- Subsequent transactions (e.g., adding Ksh 50 to a category already at 100%) will attempt to write a 100% notification record, naturally hit the unique constraint, and fail silently without re-firing the push notification.

## 3. The "Jump" Edge Case
If a single, large transaction pushes your spending from under 80% straight past 100%, the logic correctly evaluates both thresholds and triggers both the 80% and 100% notifications. (The notification IDs have been uniquely seeded with the percentage to ensure they don't overwrite each other in the notification tray).

## 4. Past vs Current Month Rules
When a transaction is parsed, the DB state is updated for that transaction's specific month (so the app knows not to fire if it parses another past transaction).
- However, we explicitly check if the transaction belongs to the *current* calendar month before actually showing the local push notification, protecting you from notification spam during historical syncs.
- During retroactive recategorization on the home tab, we run the budget check against *both* the transaction's original month (to silently log the DB state) and the *current* month (so if your rule update pushes *this month's* spending over 80%, you get correctly notified).

## Verification
A new unit test suite (`test/database/budget_notification_test.dart`) was written and has successfully passed all scenarios, specifically confirming:
- The "jump" logic creates exactly two notification records.
- The unique constraint successfully catches and silences subsequent transactions after a threshold is hit.
