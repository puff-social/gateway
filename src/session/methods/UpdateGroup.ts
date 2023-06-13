import { Event, Op, UserFlags } from "@puff-social/commons";

import { Session } from "..";
import { Groups, sendPublicGroups } from "../../data";
import { groupUpdate } from "../../validators/group";

interface Data {
  name: string;
  visbility: "public" | "private";
}

export async function UpdateGroup(this: Session, data: Data) {
  if (!this.group_id)
    return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

  const group = Groups.get(this.group_id);

  if (!group)
    return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

  if (
    this.id != group.owner_session_id &&
    !(this.user?.flags || 0 & UserFlags.admin)
  )
    return this.error(Event.GroupActionError, { code: "NOT_OWNER" });

  const validate = await groupUpdate.parseAsync(data);

  if (!validate)
    return this.error(Event.GroupActionError, { code: "INVALID_DATA" });

  for (const key of Object.keys(validate)) group[key] = validate[key];

  group?.broadcast({ op: Op.Event, event: Event.GroupUpdate }, validate);

  if (group.visibility == "public") sendPublicGroups();
}
