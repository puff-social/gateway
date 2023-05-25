import { Event, Op } from "@puff-social/commons";

import { Session } from "..";
import { Groups } from "../../data";
import { getUserByToken } from "../../helpers/hash";

interface Data {
  token: string;
}

export async function LinkUser(this: Session, data: Data) {
  const user = await getUserByToken(data.token);
  if (!user) return;

  this.user = user;

  this.send(
    { op: Op.Event, event: Event.UserLinkSuccess },
    { id: this.user.id }
  );

  if (!this.group_id) return;

  const group = Groups.get(this.group_id);

  group?.broadcast(
    { op: Op.Event, event: Event.GroupUserUpdate },
    {
      group_id: group.id,
      session_id: this.id,
      disconnected: this.disconnected,
      user: this.user,
    }
  );
}
