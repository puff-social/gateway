import { z } from "zod";

export const deviceUpdate = z
  .object({
    deviceName: z.string(),
    deviceMac: z.string(),
    deviceModel: z.string(),
    deviceSeries: z.number().optional(),
    serialNumber: z.string(),
    brightness: z.number(),
    temperature: z.number().nullable(),
    battery: z.number(),
    state: z.number(),
    stateTime: z.number(),
    totalDabs: z.number(),
    dabsPerDay: z.number(),
    chamberType: z.number().min(0).max(3),
    chargeSource: z.union([
      z.literal(0),
      z.literal(1),
      z.literal(2),
      z.literal(3),
    ]),
    activeColor: z.object({ r: z.number(), g: z.number(), b: z.number() }),
    profile: z.object({
      name: z.string(),
      temp: z.number(),
      time: z.string(),
      color: z.string().optional(),
      moodId: z.string().optional(),
      intensity: z.number().optional(),
    }),
    utcTime: z.number(),
    lastDab: z
      .object({
        totalTime: z.number(),
        timeElapsed: z.number(),
        nominalTemp: z.number(),
        actualTemp: z.number(),
        timestamp: z.number(),
      })
      .optional(),
  })
  .partial()
  .strip()
  .nullish();
