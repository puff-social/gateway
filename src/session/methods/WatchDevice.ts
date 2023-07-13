import { Event } from "@puff-social/commons";

import { Session } from "..";
import { watchDevice } from "../../validators/session";

interface Data {
  id: string;
}

export async function WatchDevice(this: Session, data: Data) {
  const validate = await watchDevice.parseAsync(data);

  if (!validate)
    return this.error(Event.GroupActionError, { code: "INVALID_DATA" });

  this.watching_devices = [
    ...(this.watching_devices || []),
    Buffer.from(data.id.split("_")[1], "base64").toString("utf8"),
  ];
}
