import { Event, Op } from "@puff-social/commons";
import { groupCreate } from "../../validators/group";
import { Groups, sendPublicGroups } from "../../data";
import { Group } from "../../group";
import { Session } from "..";

interface Data {
  name?: string;
  visibility?: "public" | "private";
}

export async function CreateGroup(this: Session, data: Data) {
  if (this.group_id)
    return this.error(Event.GroupCreateError, {
      code: "already_in_a_group",
    });

  const payload = await groupCreate.parseAsync(data);
  const group = new Group({
    owner: this.id,
    name: payload?.name,
    visilibity: payload?.visibility,
  });

  Groups.set(group.id, group);

  this.strain = undefined;
  this.group_id = group?.id;

  const date = new Date();

  group.members.set(this.id, { id: this.id, joined: date });

  group.broadcast(
    { op: Op.Event, event: Event.GroupUserJoin, ignored: [this.id] },
    {
      group_id: this.id,
      group_joined: date.toISOString(),
      session_id: this.id,
      away: this.away,
      disconnected: this.disconnected,
      mobile: this.mobile,
      strain: this.strain,
      user: this.user,
    }
  );

  this.send(
    { op: Op.Event, event: Event.GroupCreate },
    {
      group_id: group.id,
      name: group.name,
      visibility: group.visibility,
      owner_session_id: this.id,
    }
  );

  const { seshers, watchers, away } = group.getMembers();

  this.send(
    { op: Op.Event, event: Event.JoinedGroup },
    {
      group_id: group.id,
      name: group.name,
      visibility: group.visibility,
      owner_session_id: this.id,
      state: group.state,
      sesh_counter: group.sesh_counter,
      ready: group.ready,
      members: [...seshers, ...watchers],
    }
  );

  if (group.visibility == "public") sendPublicGroups();
}
