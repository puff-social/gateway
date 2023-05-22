import { Event, Op } from "@puff-social/commons";

import { Session } from "..";
import { Groups, Sessions } from "../../data";

export async function InquireHeat(this: Session) {
  try {
    if (!this.group_id)
      return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

    const group = Groups.get(this.group_id);

    if (!group)
      return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

    const { watchers, away } = group.getMembers();

    group.state = "awaiting";

    group?.broadcast(
      { op: Op.Event, event: Event.GroupUpdate },
      {
        state: group.state,
      }
    );

    for (const { id } of Array.from(group.members, ([, { id }]) => ({
      id,
    }))) {
      const session = Sessions.get(id);
      session?.send(
        { op: Op.Event, event: Event.GroupHeatInquiry },
        {
          session_id: this.id,
          watcher: !!watchers.find((mem) => mem.session_id == session.id),
          away: !!away.find((mem) => mem.session_id == session.id),
        }
      );
    }
  } catch (error) {
    return this.error(Event.GroupActionError, { code: "INVALID_DATA" });
  }
}
