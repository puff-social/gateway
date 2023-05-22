import { Event, Op } from "@puff-social/commons";

import { Session } from "..";
import { Groups } from "../../data";
import { groupReaction } from "../../validators/group";

export interface Data {
  emoji: string;
}

export async function SendReaction(this: Session, data: Data) {
  try {
    if (!this.group_id)
      return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

    const group = Groups.get(this.group_id);

    if (!group)
      return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

    const validate = await groupReaction.parseAsync(data);

    if (!validate)
      return this.error(Event.GroupActionError, { code: "INVALID_DATA" });

    group?.broadcast(
      { op: Op.Event, event: Event.GroupReaction },
      {
        group_id: group.id,
        author_session_id: this.id,
        emoji: validate.emoji,
      }
    );
  } catch (error) {
    return this.error(Event.GroupActionError, { code: "INVALID_DATA" });
  }
}
