import {
  ChamberType,
  ChargeSource,
  Colors,
  DeviceState,
  GatewayDeviceProfile,
} from "@puff-social/commons/dist/puffco";
import { keydb } from "@puff-social/commons/dist/connectivity/keydb";
import { Event, Op } from "@puff-social/commons";

import { Session } from "..";
import { Groups } from "../../data";
import { deviceUpdate } from "../../validators/device";
import { StartWithReady } from "./StartWithReady";

interface Data {
  deviceName: string;
  deviceMac?: string;
  deviceModel: string;
  brightness: number;
  temperature: number;
  battery: number;
  state: number;
  totalDabs: number;
  activeColor: Colors;
  chargeSource: ChargeSource;
  profile: GatewayDeviceProfile;
  chamberType: ChamberType;
}

export async function SendDeviceState(this: Session, data: Data) {
  try {
    if (!this.group_id)
      return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

    const group = Groups.get(this.group_id);

    if (!group)
      return this.error(Event.GroupActionError, { code: "NOT_IN_GROUP" });

    const validate = await deviceUpdate.parseAsync(data);
    if (!validate)
      return this.error(Event.GroupActionError, { code: "INVALID_DATA" });

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
        joined: group.members.get(this.id)?.joined.getDate(),
      });

    if (!this.away && "state" in validate) {
      if (group.state == "awaiting" && validate.state == 6) {
        group.ready = [...group.ready, this.id];
        group?.broadcast(
          { op: Op.Event, event: Event.GroupUpdate },
          {
            ready: group.ready,
          }
        );

        const { seshers } = group.getMembers();
        if (seshers.length == group.ready.length) StartWithReady.bind(this)();
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
      { op: Op.Event, event: Event.GroupUserDeviceUpdate },
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
