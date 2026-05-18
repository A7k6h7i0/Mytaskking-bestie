'use strict';

/**
 * Bestie — task scoring.
 *
 * Each TaskAssignee row gets a 0-100 score at the moment the assignee marks
 * the task `COMPLETED`. The score lives forever on that row so we can
 * compute leaderboards and per-user averages without touching the task
 * itself again.
 *
 * Formula:
 *   on_time = clamp(100 + min(0, hoursEarlyOrLate) * 5, 10, 100)
 *   priority_mult = { LOW: 0.9, MEDIUM: 1.0, HIGH: 1.1, URGENT: 1.2 }
 *   score = round( on_time × priority_mult ), capped at 100
 *
 * Examples:
 *   - on-time MEDIUM           → 100
 *   - 3h late MEDIUM           → 100 - 15 = 85
 *   - 12h late HIGH            → (100 - 60) × 1.1 = 44
 *   - 24h late URGENT          → max(10, 100 - 120) × 1.2 = 12
 *   - completed before due URGENT → min(100, 100 × 1.2) = 100 (URGENT can't exceed 100)
 *   - no dueAt set             → 70 (neutral — no time pressure data)
 *
 * The reason string is human-readable; we surface it on the assignee's task
 * card so the score never feels black-box.
 */

const PRIORITY_MULT = { LOW: 0.9, MEDIUM: 1.0, HIGH: 1.1, URGENT: 1.2 };

function compute({ dueAt, completedAt, priority = 'MEDIUM' }) {
  // No due date → neutral default. The scoring engine still loves you, it
  // just has nothing to grade on-time-ness against.
  if (!dueAt) return { score: 70, reason: 'Completed (no due date set)' };

  const due = new Date(dueAt).getTime();
  const done = new Date(completedAt || Date.now()).getTime();
  const hours = (due - done) / 3_600_000;             // positive = early, negative = late

  let onTime = 100 + Math.min(0, hours) * 5;          // -5 per hour late
  onTime = Math.max(10, Math.min(100, onTime));

  const mult = PRIORITY_MULT[priority] ?? 1.0;
  const score = Math.max(0, Math.min(100, Math.round(onTime * mult)));

  let reason;
  if (hours >= 0) {
    reason = hours >= 1
      ? `On time — finished ${Math.floor(hours)}h early`
      : 'On time';
  } else {
    const late = Math.abs(hours);
    reason = late >= 1
      ? `Late — ${Math.floor(late)}h past due`
      : 'Late — under an hour';
  }
  if (priority !== 'MEDIUM') reason += ` · ${priority} priority`;

  return { score, reason };
}

/** Average + on-time rate + total + streak for one user. */
async function userSummary(prisma, userId) {
  const rows = await prisma.taskAssignee.findMany({
    where: { userId, state: 'COMPLETED' },
    orderBy: { completedAt: 'desc' },
    select: { score: true, completedAt: true, task: { select: { dueAt: true } } },
  });
  if (rows.length === 0) {
    return { total: 0, avgScore: 0, onTimeRate: 0, streak: 0, lastScore: null };
  }
  const total = rows.length;
  const sum = rows.reduce((acc, r) => acc + (r.score ?? 0), 0);
  const onTime = rows.filter((r) => {
    if (!r.task?.dueAt) return true;
    return new Date(r.completedAt) <= new Date(r.task.dueAt);
  }).length;

  // Streak = how many of the most-recent completions were on time, in a row.
  let streak = 0;
  for (const r of rows) {
    const ok = !r.task?.dueAt || new Date(r.completedAt) <= new Date(r.task.dueAt);
    if (!ok) break;
    streak++;
  }

  return {
    total,
    avgScore: Math.round(sum / total),
    onTimeRate: Math.round((onTime / total) * 100),
    streak,
    lastScore: rows[0].score,
  };
}

module.exports = { compute, userSummary, PRIORITY_MULT };
