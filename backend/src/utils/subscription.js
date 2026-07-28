'use strict';

function isActivePaidSubscription(sub) {
  if (!sub || sub.status !== 'PAID') return false;
  if (!sub.paidUntil) return true;
  return new Date(sub.paidUntil) > new Date();
}

function activePaidPlanMessage(sub) {
  const plan =
    sub?.billingPlan?.label ||
    (sub?.planMonths ? `${sub.planMonths} month plan` : 'paid plan');
  const until = sub?.paidUntil
    ? new Date(sub.paidUntil).toISOString().slice(0, 10)
    : '';
  if (until) {
    return `You are already on the ${plan} plan (active until ${until}).`;
  }
  return `You are already on the ${plan} plan.`;
}

module.exports = {
  isActivePaidSubscription,
  activePaidPlanMessage,
};
