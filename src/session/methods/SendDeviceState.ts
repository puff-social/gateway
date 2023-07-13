import { DeviceState } from "@puff-social/commons/dist/puffco";
import { keydb } from "@puff-social/commons/dist/connectivity/keydb";
import { Event, Op } from "@puff-social/commons";

import { Session } from "..";
import { Groups, Sessions } from "../../data";
import { deviceUpdate } from "../../validators/device";
import { StartWithReady } from "./StartWithReady";

export async function SendDeviceState(this: Session, data: DeviceState) {
  try {
    if (!this.group_id)
      return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

    const group = Groups.get(this.group_id);

    if (!group)
      return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

    const validate = await deviceUpdate.parseAsync(data);
    if (!validate)
      return this.error(Event.GroupActionError, { code: "INVALID_DATA" });

    if (
      (this.device_state?.deviceMac || validate.deviceMac) &&
      ("totalDabs" in validate ||
        "dabsPerDay" in validate ||
        "lastDab" in validate) &&
      (this.device_state?.totalDabs != validate?.totalDabs ||
        this.device_state?.dabsPerDay != validate?.dabsPerDay ||
        this.device_state?.lastDab != validate?.lastDab)
    ) {
      for (const { id } of Array.from(Sessions, ([, { id }]) => ({
        id,
      }))) {
        const session = Sessions.get(id);
        if (
          session?.watching_devices?.includes(
            (this.device_state?.deviceMac ?? validate.deviceMac) as string
          )
        )
          session?.send(
            {
              op: Op.Event,
              event: Event.WatchedDeviceUpdate,
            },
            {
              id: `device_${Buffer.from(
                (this.device_state?.deviceMac ?? validate.deviceMac) as string
              ).toString("base64")}`,
              dabs: validate.totalDabs,
              dabsPerDay: validate.dabsPerDay,
              lastDab: validate.lastDab,
            }
          );
      }
    }

    if (!this.device_state) this.device_state = validate as DeviceState;
    else
      for (const key of Object.keys(validate))
        this.device_state[key] = validate[key];

    if (validate.deviceMac)
      await keydb.hset(`devices/${validate.deviceMac}/presence`, {
        session_id: this.id,
        user_id: this.user?.id,
        group_id: this.group_id,
        away: this.away,
        mobile: this.mobile,
        joined: group.members.get(this.id)?.joined.toISOString(),
      });

    if (!this.away && "state" in validate) {
      if (
        group.state == "awaiting" &&
        validate.state == 6 &&
        !group.ready.includes(this.id)
      ) {
        group.ready = [...group.ready, this.id];
        group?.broadcast(
          { op: Op.Event, event: Event.GroupUpdate },
          {
            ready: group.ready,
          }
        );

        const { seshers, away } = group.getMembers();
        if (seshers.length - away.length == group.ready.length)
          StartWithReady.bind(this)();
      } else if (group.state == "seshing" && validate.state == 7) {
        group.sesh_counter = group.sesh_counter + 1;
        group.ready = [];
        group.state = "chilling";
        group?.broadcast(
          { op: Op.Event, event: Event.GroupUpdate },
          {
            sesh_counter: group.sesh_counter,
            state: "chilling",
            ready: group.ready,
          }
        );
      }
    }

    group?.broadcast(
      { op: Op.Event, event: Event.GroupUserDeviceUpdate, ignored: [this.id] },
      {
        group_id: group.id,
        session_id: this.id,
        device_state: validate,
      }
    );
  } catch (error) {
    return this.error(Event.GroupActionError, { code: "INVALID_DATA" });
  }
}
