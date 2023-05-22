import { users } from "@prisma/client";
import { Op, Event } from "@puff-social/commons";
import { DeviceState } from "@puff-social/commons/dist/puffco/constants";

import { v4 } from "uuid";
import EventEmitter from "events";
import { WebSocket } from "ws";
import { generateString } from "../util";
import { SocketMessage } from "../types/Socket";
import { LinkUser } from "./methods/LinkUser";
import { LeaveGroup } from "./methods/LeaveGroup";
import { JoinGroup } from "./methods/JoinGroup";
import { CreateGroup } from "./methods/CreateGroup";
import { UpdateGroup } from "./methods/UpdateGroup";
import { SendDeviceState } from "./methods/SendDeviceState";
import { InquireHeat } from "./methods/InquireHeat";
import { StopHeat } from "./methods/StopHeat";
import { StartWithReady } from "./methods/StartWithReady";
import { TransferGroupOwner } from "./methods/TransferGroupOwner";
import { SendReaction } from "./methods/SendReaction";
import { DeleteGroup } from "./methods/DeleteGroup";
import { KickMember } from "./methods/KickMember";
import { SendMessage } from "./methods/SendMessage";
import { DisconnectDevice } from "./methods/DisconnectDevice";
import { UpdateState } from "./methods/UpdateState";

export interface Session {
  id: string;
  token: string;

  disconnected: boolean;
  mobile: boolean;
  away: boolean;

  strain?: string;
  group_id?: string;
  device_state?: DeviceState;
  user?: users;

  socket: WebSocket;
}

export class Session extends EventEmitter {
  constructor(socket: WebSocket) {
    super();

    this.id = v4();
    this.token = generateString(32, { lower: true, chars: true });

    this.disconnected = false;
    this.mobile = false;
    this.away = false;

    this.socket = socket;

    this.socket.on("message", (message) => {
      try {
        const data = JSON.parse(message.toString());
        this.handle(data);
      } catch (error) {}
    });

    socket.send(
      JSON.stringify({
        op: Op.Hello,
        d: {
          session_id: this.id,
          session_token: this.token,
          heartbeat_interval: 5_000,
        },
      })
    );
  }

  error(event: Event, data?: { code: string } | Record<string, any>) {
    if (this.socket.readyState != this.socket.OPEN) return;
    this.socket.send(JSON.stringify({ op: Op.Event, t: event, d: data }));
  }

  send(head: { op: Op; event?: Event }, data?: any) {
    if (this.socket.readyState != this.socket.OPEN) return;
    this.socket.send(JSON.stringify({ op: head.op, t: head.event, d: data }));
  }

  close() {
    if (this.group_id) LeaveGroup.bind(this)();
  }

  private async handle(data: SocketMessage) {
    switch (data.op) {
      case Op.Join: {
        JoinGroup.bind(this, data.d)();
        break;
      }
      case Op.CreateGroup: {
        CreateGroup.bind(this, data.d)();
        break;
      }
      case Op.SendDeviceState: {
        SendDeviceState.bind(this, data.d)();
        break;
      }
      case Op.UpdateGroup: {
        UpdateGroup.bind(this)(data.d);
        break;
      }
      case Op.UpdateUser: {
        UpdateState.bind(this, data.d)();
        break;
      }
      case Op.LeaveGroup: {
        LeaveGroup.bind(this)();
        break;
      }
      case Op.InquireHeating: {
        InquireHeat.bind(this)();
        break;
      }
      case Op.StartWithReady: {
        StartWithReady.bind(this)();
        break;
      }
      case Op.DisconnectDevice: {
        DisconnectDevice.bind(this)();
        break;
      }
      case Op.SendMessage: {
        SendMessage.bind(this, data.d)();
        break;
      }
      case Op.StopAwaiting: {
        StopHeat.bind(this)();
        break;
      }
      case Op.ResumeSession: {
        console.log("User resumed session");
        break;
      }
      case Op.SendReaction: {
        SendReaction.bind(this, data.d)();
        break;
      }
      case Op.DeleteGroup: {
        DeleteGroup.bind(this)();
        break;
      }
      case Op.TransferOwnership: {
        TransferGroupOwner.bind(this, data.d)();
        break;
      }
      case Op.KickFromGroup: {
        KickMember.bind(this)();
        break;
      }
      case Op.AwayState: {
        this.send({ op: Op.Event, event: Event.Deprecated });
        break;
      }
      case Op.GroupStrain: {
        this.send({ op: Op.Event, event: Event.Deprecated });
        break;
      }
      case Op.LinkUser: {
        LinkUser.bind(this, data.d)();
        break;
      }
      case Op.SetMobile: {
        this.send({ op: Op.Event, event: Event.Deprecated });
        break;
      }

      default:
        break;
    }
  }
}
