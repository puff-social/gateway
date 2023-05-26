import { users } from "@prisma/client";

import { env } from "../env";
import { connections } from "@puff-social/commons";

export async function verifyByToken(token: string) {
  const json: {
    valid: boolean;
    user: users;
    connection: connections;
    voice?: { id: string; name: string };
  } = await fetch(`${env.INTERNAL_API}/verify`, {
    headers: {
      authorization: token,
    },
  }).then((r) => r.json());

  if (!json.valid) return null;
  return json;
}
