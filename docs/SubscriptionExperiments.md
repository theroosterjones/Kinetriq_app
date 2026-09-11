# Trial length: 7 days vs 14 days

App Store Connect configuration, not a code change. Nothing in the app reads the
trial length — RevenueCat reports whatever Apple grants — so this ships without a
binary release.

## Why it's worth testing

Kinetriq's value shows up in *comparison*, and comparison needs more than one
session. A user who installs on a Sunday, analyzes one squat set, and never opens the
app again during a 7-day window sees a single score with nothing to compare it to.
Now that history persists and the Progress tab computes trends across sessions,
`TrendInsights` needs **three** sessions before it says anything at all
(`TrendInsights.minimumSessions`).

For someone lifting three or four times a week, hitting three sessions of the *same
movement* inside seven days is genuinely unlikely. Fourteen days makes it routine.
The trial is currently expiring before the product's best argument has a chance to
appear on screen.

The risk is the ordinary one: a longer trial means more time to forget, and the
cancel rate at day 14 may be worse than at day 7. That is what the test measures.

## How to run it

App Store Connect → **Kinetriq** → Subscriptions → *Kinetriq Pro* group.

1. Select `com.kevinkjones.kinetriq.monthly`.
2. **Subscription Prices → Introductory Offers → Create Introductory Offer**.
3. End the current 7-day free-trial offer with an end date rather than deleting it —
   anyone mid-trial keeps what they started with, and you keep the record of what the
   old cohort got.
4. Create the replacement: **Free Trial**, **2 weeks**, all territories, start date
   the day after the old offer ends.
5. Repeat for `com.kevinkjones.kinetriq.annual` so someone who picks annual is not
   quietly offered a worse deal.

Apple does not run A/B tests on introductory offers, so this is sequential: a clean
cohort of 7-day trials, then a clean cohort of 14-day trials.

## What to measure

Wait until each window has at least **30 started trials** before reading anything.
Below that, one or two people moving is the entire difference.

RevenueCat → Charts, segmented by the date the trial started:

| Metric | Where | What matters |
|---|---|---|
| Trial → paid conversion | Charts → Conversion to Paying | The headline number |
| Trial start count | Charts → Trials Started | Confirms traffic didn't change underneath you |
| Refund / cancel rate in month 1 | Charts → Churn | A longer trial that converts worse-qualified users shows up here, not above |

Conversion is the number to compare, but check the third row before concluding. A
14-day trial that converts slightly better and then churns in month one is worse than
a 7-day trial that converts slightly worse.

## The thing to check first

Before changing the length at all, confirm how many trial users reach three saved
sessions. Once metrics sync is live, that is one query:

```sql
select
  count(*) filter (where sessions >= 3) as reached_three,
  count(*) as total
from (
  select user_id, count(*) as sessions
  from analysis_records
  where recorded_at < created_at + interval '7 days'
  group by user_id
) t;
```

If most trial users already hit three sessions inside a week, the trial length is not
the constraint and this test will come back flat. Spend the time on activation
instead — the first-run path from install to first analyzed set.
