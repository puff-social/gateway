import { Event, Op } from "@puff-social/commons";

import { Session } from "..";
import { Groups } from "../../data";

export async function StopHeat(this: Session) {
  try {
    if (!this.group_id)
      return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

    const group = Groups.get(this.group_id);

    if (!group)
      return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

    group.state = "chilling";
    group.ready = [];

    group?.broadcast(
      { op: Op.Event, event: Event.GroupUpdate },
      {
        state: group.state,
        ready: [],
      }
    );
  } catch (error) {
    return this.error(Event.GroupActionError, { code: "INVALID_DATA" });
  }
}
