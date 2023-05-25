import { Event, Op } from "@puff-social/commons";
import { keydb } from "@puff-social/commons/dist/connectivity/keydb";

import { Session } from "..";
import { Groups } from "../../data";

export async function DisconnectDevice(this: Session) {
  try {
    if (!this.group_id)
      return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

    const group = Groups.get(this.group_id);

    if (!group)
      return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

    if (!this.device_state)
      return this.error(Event.GroupActionError, {
        code: "NO_DEVICE_CONNECTED",
      });

    if (this.device_state.deviceMac)
      await keydb.del(`devices/${this.device_state.deviceMac}/presence`);

    this.device_state = undefined;

    group?.broadcast(
      { op: Op.Event, event: Event.GroupUserDeviceDisconnect },
      {
        group_id: group.id,
        session_id: this.id,
      }
    );
  } catch (error) {
    return this.error(Event.GroupActionError, { code: "INVALID_DATA" });
  }
}
