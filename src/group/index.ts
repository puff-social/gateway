import { Event, Op } from "@puff-social/commons";
import EventEmitter from "events";

import { randomStrain } from "./utils";
import { generateString } from "../util";
import { Groups, Sessions, sendPublicGroups } from "../data";
import { Session } from "../session";
import { validState } from "@puff-social/commons/dist/puffco";

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

    this.id = options.id ?? generateString(6, { lower: true, chars: false });
    this.name = options.name ?? randomStrain();
    this.visibility = options.visilibity ?? "private";
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
        if (!member || !member.device_state || !validState(member.device_state))
          return false;
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
          voice: member.voice,
        };
      });

    const watchers = Array.from(this.members, ([, member]) => member)
      .filter((mem) => {
        const member = Sessions.get(mem.id);
        if (!member || (member.device_state && validState(member.device_state)))
          return false;
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
          voice: member.voice,
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
          voice: member.voice,
        };
      });

    return { seshers, watchers, away };
  }

  delete() {
    this.broadcast(
      { op: Op.Event, event: Event.GroupDelete },
      { group_id: this.id }
    );

    Groups.delete(this.id);

    sendPublicGroups();
  }

  broadcast(head: { op: Op; event?: Event; ignored?: string[] }, data?: any) {
    this.members.forEach((member) => {
      try {
        if (head.ignored?.includes(member.id)) return;
        const session = Sessions.get(member.id);
        session?.send(head, data);
      } catch (error) {}
    });
  }
}
