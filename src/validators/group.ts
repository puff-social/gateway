import { z } from "zod";
import { NAME_REGEX } from "../constants";
import { randomStrain } from "../group/utils";

export const groupJoin = z.object({
  group_id: z.string(),
});

const nameValidation = z.custom<{ arg: string }>((val) =>
  typeof val === "string" ? !RegExp(NAME_REGEX, 'gi').test(val) : false,
  'name contains an invalid string'
);

export const groupCreate = z
  .object({
    id: z.string().max(16).optional(),
    name: z.string().max(32).optional(),
    visibility: z.enum(["public", "private"]).default("private").optional(),
    persistent: z.boolean().optional(),
  })
  .optional()
  .refine((obj) => {
    if (obj?.name && RegExp(NAME_REGEX, 'gi').test(obj?.name))
      obj.name = randomStrain();

    return obj;
  });

export const groupUpdate = z
  .object({
    name: z.string().max(32).and(nameValidation).optional(),
    visibility: z.enum(["public", "private"]).default("private").optional(),
    persistent: z.boolean().optional(),
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
