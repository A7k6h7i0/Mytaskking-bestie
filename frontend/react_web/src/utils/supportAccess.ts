import type { User } from '@/store/auth';

export const ASSIGNEE_UPDATE_STATUSES = ['IN_PROGRESS', 'RESOLVED', 'CLOSED'] as const;

export function assigneeStatusOptions<T extends { value: string }>(all: T[]): T[] {
  return all.filter((s) => (ASSIGNEE_UPDATE_STATUSES as readonly string[]).includes(s.value));
}

export function defaultAssigneeStatus(current: string): string {
  return (ASSIGNEE_UPDATE_STATUSES as readonly string[]).includes(current)
    ? current
    : 'IN_PROGRESS';
}

export function isPlatformSuperAdmin(user: User | null | undefined): boolean {
  if (!user || user.role !== 'SUPER_ADMIN') return false;
  const tenantId = user.tenantId || user.tenant?.id || 'default';
  return tenantId === 'default';
}

export function isDefaultTenantSupportAssignee(user: User | null | undefined): boolean {
  if (!user || user.isClient) return false;
  if (user.role === 'SUPER_ADMIN' || user.role === 'ADMIN') return false;
  const tenantId = user.tenantId || user.tenant?.id || 'default';
  const slug = user.tenant?.slug;
  return tenantId === 'default' && (!slug || slug === 'default');
}

export function canAccessSupportIssues(user: User | null | undefined): boolean {
  return isPlatformSuperAdmin(user) || isDefaultTenantSupportAssignee(user);
}

export function canReportProblem(user: User | null | undefined): boolean {
  if (!user || user.isClient) return false;
  return !isPlatformSuperAdmin(user);
}

export function assigneeCanUpdateIssueStatus(options: {
  isSuperAdmin: boolean;
  ticketStatus: string;
  assigneeIds: string[];
  userId?: string;
}): boolean {
  if (options.isSuperAdmin) return true;
  if (options.ticketStatus === 'CLOSED') return false;
  if (!options.userId) return false;
  return options.assigneeIds.includes(options.userId);
}
