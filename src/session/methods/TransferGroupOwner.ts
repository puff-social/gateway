import { Event, Op, UserFlags } from "@puff-social/commons";

import { Session } from "..";
import { Groups } from "../../data";
import { groupOwnerTransfer } from "../../validators/group";

export interface Data {
  session_id: string;
}

export async function TransferGroupOwner(this: Session, data: Data) {
  try {
    if (!this.group_id)
      return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

    const group = Groups.get(this.group_id);

    if (!group)
      return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

    if (
      group.owner_session_id != this.id &&
      !(this.user?.flags || 0 & UserFlags.admin)
    )
      return this.error(Event.GroupActionError, { code: "NOT_OWNER" });

    if (!group.members.get(data.session_id))
      return this.error(Event.GroupActionError, { code: "USER_NOT_IN_GROUP" });

    const validate = await groupOwnerTransfer.parseAsync(data);

    if (!validate)
      return this.error(Event.GroupActionError, { code: "INVALID_DATA" });

    group.owner_session_id = data.session_id;

    group?.broadcast(
      { op: Op.Event, event: Event.GroupUpdate },
      {
        owner_session_id: data.session_id,
      }
    );
  } catch (error) {
    return this.error(Event.GroupActionError, { code: "INVALID_DATA" });
  }
}
