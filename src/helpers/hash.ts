import { users } from "@prisma/client";

import { env } from "../env";

export async function getUserByToken(token: string) {
  const json: { valid: boolean; user: users } = await fetch(
    `${env.INTERNAL_API}/verify`,
    {
      headers: {
        authorization: token,
      },
    }
  ).then((r) => r.json());

  if (!json.valid) return null;
  return json.user;
}
