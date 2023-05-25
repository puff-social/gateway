import { keydb } from "@puff-social/commons/dist/connectivity/keydb";

export async function checkRateLimit(
  key: string,
  session: string,
  limit: { interval: number; limit: number }
): Promise<boolean> {
  const redisKey = `ratelimits:${key}/${session}`;

  const count = await keydb.incr(redisKey);
  if (count === 1) {
    await keydb.expire(redisKey, limit.interval);
  }

  return count <= limit.limit;
}
