import { users } from "@prisma/client";
import { Op, Event, VoiceChannelState } from "@puff-social/commons";
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
import { ResumeSession } from "./methods/ResumeSession";
import { checkRateLimit } from "../ratelimit";
import { Heartbeat } from "./methods/Heartbeat";
import { Groups } from "../data";

export interface Session {
  id: string;
  token: string;

  disconnected: boolean;
  mobile: boolean;
  away: boolean;

  strain?: string;
  group_id?: string;
  device_state?: DeviceState;
  voice?: VoiceChannelState;
  user?: users;

  alive_timer: NodeJS.Timer;
  last_heartbeat: Date;

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
          heartbeat_interval: 10_000,
        },
      })
    );

    this.startAliveTimer();
  }

  resume() {
    this.socket.on("message", (message) => {
      try {
        const data = JSON.parse(message.toString());
        this.handle(data);
      } catch (error) {}
    });

    this.startAliveTimer();
  }

  startAliveTimer() {
    this.last_heartbeat = new Date();
    this.alive_timer = setInterval(() => {
      if (new Date().getTime() - this.last_heartbeat.getTime() >= 15 * 1000) {
        if (this.socket.readyState == this.socket.OPEN)
          this.socket.close(4002, "HEARTBEAT_NOT_RECEIVED");
        if (this.alive_timer) clearInterval(this.alive_timer);
      }
    }, 15 * 1000);
  }

  error(event: Event, data?: { code: string } | Record<string, any>) {
    if (this.socket.readyState != this.socket.OPEN) return;
    this.socket.send(JSON.stringify({ op: Op.Event, t: event, d: data }));
  }

  send(head: { op: Op; event?: Event }, data?: any) {
    if (this.socket.readyState != this.socket.OPEN) return;
    this.socket.send(JSON.stringify({ op: head.op, t: head.event, d: data }));
  }

  close(code?: number, reason?: string) {
    if (this.group_id) LeaveGroup.bind(this)();
    if (this.socket.readyState == this.socket.OPEN)
      this.socket.close(code, reason);
    if (this.alive_timer) clearInterval(this.alive_timer);
  }

  updateUser(user: users) {
    this.user = user;

    if (!this.group_id) return;
    const group = Groups.get(this.group_id);
    group?.broadcast(
      { op: Op.Event, event: Event.GroupUserUpdate },
      {
        session_id: this.id,
        group_id: group.id,
        user: this.user,
        voice: this.voice,
      }
    );
  }

  private handlers: {
    name: string;
    func?: Function;
    deprecated?: boolean;
    op: Op;
    ratelimit?: { interval: number; limit: number };
  }[] = [
    {
      name: "join_group",
      op: Op.Join,
      func: JoinGroup,
      ratelimit: {
        interval: 5 * 1000,
        limit: 2,
      },
    },
    {
      name: "create_group",
      op: Op.CreateGroup,
      func: CreateGroup,
      ratelimit: {
        interval: 30 * 1000,
        limit: 1,
      },
    },
    {
      name: "send_device_state",
      op: Op.SendDeviceState,
      func: SendDeviceState,
    },
    {
      name: "update_group",
      op: Op.UpdateGroup,
      func: UpdateGroup,
      ratelimit: {
        interval: 10 * 1000,
        limit: 10,
      },
    },
    {
      name: "update_user_state",
      op: Op.UpdateUser,
      func: UpdateState,
      ratelimit: {
        interval: 10 * 1000,
        limit: 10,
      },
    },
    {
      name: "leave_group",
      op: Op.LeaveGroup,
      func: LeaveGroup,
    },
    {
      name: "inquire_heat",
      op: Op.InquireHeating,
      func: InquireHeat,
      ratelimit: {
        interval: 10 * 1000,
        limit: 3,
      },
    },
    {
      name: "ready_start",
      op: Op.StartWithReady,
      func: StartWithReady,
      ratelimit: {
        interval: 10 * 1000,
        limit: 1,
      },
    },
    {
      name: "disconnect_device",
      op: Op.DisconnectDevice,
      func: DisconnectDevice,
    },
    {
      name: "send_group_message",
      op: Op.SendMessage,
      func: SendMessage,
      ratelimit: {
        interval: 10 * 1000,
        limit: 10,
      },
    },
    {
      name: "stop_sesh",
      op: Op.StopAwaiting,
      func: StopHeat,
      ratelimit: {
        interval: 10 * 1000,
        limit: 3,
      },
    },
    {
      name: "resume_session",
      op: Op.ResumeSession,
      func: ResumeSession,
      ratelimit: {
        interval: 60 * 1000,
        limit: 1,
      },
    },
    {
      name: "send_reaction",
      op: Op.SendReaction,
      func: SendReaction,
      ratelimit: {
        interval: 5 * 1000,
        limit: 15,
      },
    },
    {
      name: "delete_group",
      op: Op.DeleteGroup,
      func: DeleteGroup,
      ratelimit: {
        interval: 10 * 1000,
        limit: 2,
      },
    },
    {
      name: "transfer_group_owner",
      op: Op.TransferOwnership,
      func: TransferGroupOwner,
      ratelimit: {
        interval: 10 * 1000,
        limit: 5,
      },
    },
    {
      name: "kick_group_member",
      op: Op.KickFromGroup,
      func: KickMember,
      ratelimit: {
        interval: 10 * 1000,
        limit: 10,
      },
    },
    {
      name: "link_user",
      op: Op.LinkUser,
      func: LinkUser,
      ratelimit: {
        interval: 60 * 1000,
        limit: 2,
      },
    },
    {
      name: "set_away_state",
      op: Op.AwayState,
      deprecated: true,
    },
    {
      name: "group_strain",
      op: Op.GroupStrain,
      deprecated: true,
    },
    {
      name: "set_mobile",
      op: Op.SetMobile,
      deprecated: true,
    },
    {
      name: "heartbeat",
      op: Op.Heartbeat,
      func: Heartbeat,
    },
  ];

  private async handle(data: SocketMessage) {
    const handler = this.handlers.find((handler) => handler.op == data.op);
    if (!handler)
      return this.send(
        { op: Op.Event, event: Event.InternalError },
        { code: "INVALID_OP_CODE" }
      );

    if (handler.ratelimit) {
      const ratelimited = await checkRateLimit(
        handler.name,
        this.id,
        handler.ratelimit
      );
      if (ratelimited) handler.func?.bind(this, data.d)();
      else
        this.send(
          { op: Op.Event, event: Event.RateLimited },
          { op: handler.op }
        );
    } else handler.func?.bind(this, data.d)();
  }
}
