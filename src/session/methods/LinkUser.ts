import { Event, Op, UserFlags } from "@puff-social/commons";

import { Session } from "..";
import { Groups } from "../../data";
import { verifyByToken } from "../../helpers/hash";
import { LeaveGroup } from "./LeaveGroup";

interface Data {
  token: string;
}

export async function LinkUser(this: Session, data: Data) {
  const verified = await verifyByToken(data.token);
  if (!verified) return;

  if (verified.user.flags & UserFlags.suspended) {
    if (this.group_id) LeaveGroup.bind(this);
    this.close(4003, "USER_SUSPENDED");
  }

  this.user = verified.user;
  this.voice = verified.voice;

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
      voice: this.voice,
    }
  );
}
