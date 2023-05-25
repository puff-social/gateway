import { z } from "zod";

export const stateUpdate = z
  .object({
    strain: z.string().max(48).nullable(),
    away: z.boolean(),
    mobile: z.boolean(),
  })
  .partial()
  .strip();

export const resumeSession = z.object({
  session_id: z.string().uuid(),
  session_token: z.string(),
});
