import { Event, Op } from "@puff-social/commons";
import EventEmitter from "events";

import { randomStrain } from "./utils";
import { generateString } from "../util";
import { Sessions } from "../data";
import { Session } from "../session";

export interface Group {
  id: string;
  name: string;
  visibility: string;
  state: string;
  sesh_counter: number;
  owner_session_id: string;

  members: Map<string, { id: string; joined: Date }>;
  ready: string[];
}

export class Group extends EventEmitter {
  constructor(options: {
    owner: string;
    name?: string;
    id?: string;
    visilibity?: string;
  }) {
    super();

    this.id = options.id || generateString(6, { lower: true, chars: false });
    this.name = options.name || randomStrain();
    this.visibility = options.visilibity || "private";
    this.state = "chilling";
    this.sesh_counter = 0;
    this.owner_session_id = options.owner;

    this.members = new Map();
    this.ready = [];
  }

  getMembers() {
    const seshers = Array.from(this.members, ([, member]) => member)
      .filter((mem) => {
        const member = Sessions.get(mem.id);
        if (!member || !member.device_state) return false;
        return true;
      })
      .map((mem) => {
        const member = Sessions.get(mem.id) as Session;
        return {
          session_id: member.id,
          device_state: member.device_state,
          away: member.away,
          group_joined: mem.joined,
          disconnected: member.disconnected,
          mobile: member.mobile,
          strain: member.strain,
          user: member.user,
        };
      });

    const watchers = Array.from(this.members, ([, member]) => member)
      .filter((mem) => {
        const member = Sessions.get(mem.id);
        if (!member || member.device_state) return false;
        return true;
      })
      .map((mem) => {
        const member = Sessions.get(mem.id) as Session;
        return {
          session_id: member.id,
          device_state: member.device_state,
          away: member.away,
          group_joined: mem.joined,
          disconnected: member.disconnected,
          mobile: member.mobile,
          strain: member.strain,
          user: member.user,
        };
      });

    const away = Array.from(this.members, ([, member]) => member)
      .filter((mem) => {
        const member = Sessions.get(mem.id);
        if (!member || !member.away) return false;
        return true;
      })
      .map((mem) => {
        const member = Sessions.get(mem.id) as Session;
        return {
          session_id: member.id,
          device_state: member.device_state,
          away: member.away,
          group_joined: mem.joined,
          disconnected: member.disconnected,
          mobile: member.mobile,
          strain: member.strain,
          user: member.user,
        };
      });

    return { seshers, watchers, away };
  }

  broadcast(head: { op: Op; event?: Event; ignored?: string[] }, data?: any) {
    for (const { id } of Array.from(this.members, ([, { id, joined }]) => ({
      id,
      joined,
    }))) {
      if (head.ignored?.includes(id)) return;
      const session = Sessions.get(id);
      session?.send(head, data);
    }
  }
}
