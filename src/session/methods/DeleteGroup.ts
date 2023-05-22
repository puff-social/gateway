import { Event, Op } from "@puff-social/commons";

import { Session } from "..";
import { Groups, sendPublicGroups } from "../../data";
import { LeaveGroup } from "./LeaveGroup";

export async function DeleteGroup(this: Session) {
  if (!this.group_id)
    return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

  const group = Groups.get(this.group_id);

  if (!group)
    return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

  if (this.id != group.owner_session_id)
    return this.error(Event.GroupActionError, { code: "NOT_OWNER" });

  group?.broadcast(
    { op: Op.Event, event: Event.GroupDelete },
    { group_id: group.id }
  );

  LeaveGroup.bind(this)();
  Groups.delete(group.id);

  sendPublicGroups();
}
