import { useQuery } from '@tanstack/react-query';
import { api } from '@/services/api';

type FlagState = { enabled: boolean; payload: unknown; description?: string };

/**
 * `const { enabled, payload } = useFeatureFlag('ai.task_summary')`
 *
 * Resolves against the server (`/flags/mine`) once per session, then caches
 * for 5 minutes. The server also caches the resolution per-user for 30 s.
 *
 * Use this for *UI* gating only — never trust it for security. The same flag
 * is enforced server-side on the routes that need it.
 */
export function useFeatureFlag(key: string): FlagState {
  const { data } = useQuery<Record<string, FlagState>>({
    queryKey: ['flags.mine'],
    queryFn: async () => (await api.get('/flags/mine')).data,
    staleTime: 5 * 60_000,
  });
  return data?.[key] || { enabled: false, payload: null };
}

export function useFeatureFlagPayload<T = unknown>(key: string): T | null {
  const { payload } = useFeatureFlag(key);
  return (payload as T) ?? null;
}
