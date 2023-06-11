import { Event, Op } from "@puff-social/commons";
import { keydb } from "@puff-social/commons/dist/connectivity/keydb";

import { Session } from "..";
import { Groups } from "../../data";
import { TransferGroupOwner } from "./TransferGroupOwner";

export async function LeaveGroup(this: Session) {
  if (!this.group_id)
    return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

  const group = Groups.get(this.group_id);
  this.strain = undefined;
  this.group_id = undefined;

  if (this.device_state && this.device_state.deviceMac)
    await keydb.del(`devices/${this.device_state.deviceMac}/presence`);

  if (group) {
    group.members.delete(this.id);
    if (group.ready.includes(this.id)) {
      group.ready = group.ready.filter((id) => id != this.id);
    }

    group.broadcast(
      { op: Op.Event, event: Event.GroupUserLeft },
      {
        group_id: group.id,
        session_id: this.id,
      }
    );

    const { seshers, watchers } = group.getMembers();
    group.broadcast(
      { op: Op.Event, event: Event.GroupUpdate },
      {
        members: [...seshers, ...watchers],
        ready: group.ready,
      }
    );

    if (group.members.size == 0) {
      setTimeout(() => {
        if (group.members.size == 0) group.delete();
      }, 30 * 1000);
    } else if (group.owner_session_id == this.id) {
      console.log(`DEBUG: Transferring ownership of group ${group.id}`);
      const [next] = Array.from(group.members)[0];
      console.log(`DEBUG: Transferring to ${next}`);
      if (next) TransferGroupOwner.bind(this)({ session_id: next });
    }
  }
}
