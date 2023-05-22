import { z } from "zod";

export const groupJoin = z.object({
  group_id: z.string(),
});

export const groupCreate = z
  .object({
    name: z.string().max(32).optional(),
    visibility: z.enum(["public", "private"]).default("private").optional(),
  })
  .optional();

export const groupUpdate = z
  .object({
    name: z.string().max(32).optional(),
    visibility: z.enum(["public", "private"]).default("private").optional(),
    owner_session_id: z.string().uuid().optional(),
  })
  .optional();

export const groupKick = z.object({
  session_id: z.string().uuid(),
});

export const groupOwnerTransfer = z.object({
  session_id: z.string().uuid(),
});

export const groupReaction = z.object({
  emoji: z.string().emoji(),
});

export const groupMessage = z.object({
  content: z.string().max(1024).min(1),
});
