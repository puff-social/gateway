import { Event, Op } from "@puff-social/commons";

import { Session } from "..";
import { Groups } from "../../data";
import { groupMessage } from "../../validators/group";

export interface Data {
  content: string;
}

export async function SendMessage(this: Session, data: Data) {
  try {
    if (!this.group_id)
      return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

    const group = Groups.get(this.group_id);

    if (!group)
      return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

    const validate = await groupMessage.parseAsync(data);

    if (!validate)
      return this.error(Event.GroupActionError, { code: "INVALID_DATA" });

    group?.broadcast(
      { op: Op.Event, event: Event.GroupMessage },
      {
        group_id: group.id,
        author_session_id: this.id,
        message: {
          ...validate,
          timestamp: new Date().getTime(),
        },
      }
    );
  } catch (error) {
    return this.error(Event.GroupActionError, { code: "INVALID_DATA" });
  }
}
