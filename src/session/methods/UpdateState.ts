import { Event, Op } from "@puff-social/commons";

import { Session } from "..";
import { Groups } from "../../data";
import { stateUpdate } from "../../validators/session";

interface Data {
  strain: string;
  away: boolean;
  mobile: boolean;
}

export async function UpdateState(this: Session, data: Data) {
  if (!this.group_id)
    return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

  const group = Groups.get(this.group_id);

  if (!group)
    return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

  const validate = await stateUpdate.parseAsync(data);

  if (!validate)
    return this.error(Event.GroupActionError, { code: "INVALID_DATA" });

  for (const key of Object.keys(validate)) this[key] = validate[key];

  group?.broadcast(
    { op: Op.Event, event: Event.GroupUserUpdate },
    {
      session_id: this.id,
      group_id: group.id,
      ...validate,
    }
  );
}
