import { Event, Op } from "@puff-social/commons";

import { Session } from "..";
import { Groups, Sessions } from "../../data";
import { LeaveGroup } from "./LeaveGroup";
import { groupKick } from "../../validators/group";

interface Data {
  session_id: string;
}

export async function KickMember(this: Session, data: Data) {
  if (!this.group_id)
    return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

  const group = Groups.get(this.group_id);

  if (!group)
    return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

  const validate = await groupKick.parseAsync(data);

  if (!validate)
    return this.error(Event.GroupActionError, { code: "INVALID_DATA" });

  if (group.owner_session_id == data.session_id)
    return this.error(Event.GroupActionError, { code: "CANNOT_KICK_OWNER" });

  if (this.id != group.owner_session_id)
    return this.error(Event.GroupActionError, { code: "NOT_OWNER" });

  const session = Sessions.get(data.session_id);
  if (session) {
    LeaveGroup.bind(session)();
    session.send(
      { op: Op.Event, event: Event.GroupUserKicked },
      { group_id: group.id }
    );
  }
}
