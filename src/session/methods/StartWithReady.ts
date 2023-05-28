import { Event, Op } from "@puff-social/commons";

import { Session } from "..";
import { Groups, Sessions } from "../../data";

export async function StartWithReady(this: Session) {
  try {
    if (!this.group_id)
      return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

    const group = Groups.get(this.group_id);

    if (!group)
      return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

    if (group.state != "awaiting")
      return this.error(Event.GroupActionError, {
        code: "INVALID_GROUP_STATE",
      });

    group.state = "seshing";

    group?.broadcast(
      { op: Op.Event, event: Event.GroupUpdate },
      {
        state: group.state,
      }
    );

    const { watchers, away } = group.getMembers();

    for (const { id } of Array.from(group.members, ([, { id }]) => ({
      id,
    }))) {
      const session = Sessions.get(id);
      session?.send(
        { op: Op.Event, event: Event.GroupHeatBegin },
        {
          session_id: this.id,
          excluded: !group.ready.includes(session.id),
          watcher: !!watchers.find((mem) => mem.session_id == session.id),
          away: !!away.find((mem) => mem.session_id == session.id),
        }
      );
    }
  } catch (error) {
    return this.error(Event.GroupActionError, { code: "INVALID_DATA" });
  }
}
