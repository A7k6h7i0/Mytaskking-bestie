'use strict';

/** Resolve @name / @userId / @everyone|@here|@channel targets in message body. */
function findMentionTargets({ body, members, authorId }) {
  const source = String(body || '').toLowerCase();
  if (!source.includes('@')) return [];
  const isBroadcast = /(^|\s)@(everyone|here|channel)\b/.test(source);
  if (isBroadcast) {
    return (members || [])
      .map((m) => m.user)
      .filter((p) => p && p.id !== authorId);
  }
  const picks = [];
  for (const member of members || []) {
    const person = member.user;
    if (!person || person.id === authorId) continue;
    const nameKey = `@${String(person.name || '').trim().toLowerCase()}`;
    const userIdKey = `@${String(person.userId || '').trim().toLowerCase()}`;
    if ((person.userId && source.includes(userIdKey)) || (person.name && source.includes(nameKey))) {
      picks.push(person);
    }
  }
  return Array.from(new Map(picks.map((item) => [item.id, item])).values());
}

function userIsMentionedInBody({ body, user, members, authorId }) {
  if (!user?.id || !body) return false;
  const targets = findMentionTargets({ body, members, authorId });
  return targets.some((t) => t.id === user.id);
}

module.exports = { findMentionTargets, userIsMentionedInBody };
