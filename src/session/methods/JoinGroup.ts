import { Event, Op } from "@puff-social/commons";

import { groupJoin } from "../../validators/group";
import { Groups } from "../../data";
import { Session } from "..";

interface Data {
  group_id: string;
}

export async function JoinGroup(this: Session, data: Data) {
  if (this.group_id)
    return this.error(Event.GroupJoinError, {
      code: "already_in_a_group",
    });

  const payload = await groupJoin.parseAsync(data);
  const group = Groups.get(payload.group_id);

  if (!group)
    return this.error(Event.GroupJoinError, {
      code: "invalid_group",
    });

  this.strain = undefined;
  this.group_id = group?.id;

  const date = new Date();

  if (group.members.size < 1) group.owner_session_id = this.id;

  group.members.set(this.id, { id: this.id, joined: date });

  group.broadcast(
    { op: Op.Event, event: Event.GroupUserJoin, ignored: [this.id] },
    {
      group_id: group.id,
      group_joined: date.toISOString(),
      session_id: this.id,
      away: this.away,
      disconnected: this.disconnected,
      mobile: this.mobile,
      strain: this.strain,
      user: this.user,
      voice: this.voice,
    }
  );

  const { seshers, watchers, away } = group.getMembers();

  this.send(
    { op: Op.Event, event: Event.JoinedGroup },
    {
      group_id: group.id,
      name: group.name,
      visibility: group.visibility,
      persistent: group.persistent,
      owner_session_id: group.owner_session_id,
      state: group.state,
      sesh_counter: group.sesh_counter,
      ready: group.ready,
      members: [...seshers, ...watchers],
    }
  );
}
