import { Event, Op } from "@puff-social/commons";

import { Group } from "./group";
import { Session } from "./session";

export const Groups = new Map<string, Group>();
export const Sessions = new Map<string, Session>();

export function getSessionByUserId(target: string) {
  for (const { id } of Array.from(Sessions, ([, { id }]) => ({
    id,
  }))) {
    const session = Sessions.get(id);
    if (session?.user?.id == target) return session;
  }
}

export function getSessionsByUserId(target: string) {
  const sessions: Session[] = [];

  for (const { id } of Array.from(Sessions, ([, { id }]) => ({
    id,
  }))) {
    const session = Sessions.get(id);

    if (session?.user?.id == target) sessions.push(session);
  }

  return sessions;
}

export function sendPublicGroups() {
  const groups = publicGroups();

  for (const { id } of Array.from(Sessions, ([, { id }]) => ({
    id,
  }))) {
    const session = Sessions.get(id);
    session?.send(
      {
        op: Op.Event,
        event: Event.PublicGroupsUpdate,
      },
      groups
    );
  }
}

export function publicGroups(id?: string) {
  const groups = Array.from(Groups, ([, group]) => group)
    .filter((group) => group.visibility == "public")
    .map((group) => {
      const { seshers, watchers } = group.getMembers();

      return {
        group_id: group.id,
        member_count: group.members.size,
        name: group.name,
        state: group.state,
        visibility: group.visibility,
        persistent: group.persistent,
        sesh_counter: group.sesh_counter,
        watcher_count: watchers.length,
        sesher_count: seshers.length,
      };
    });

  return groups;
}

export function getGroup(id: string) {
  const group = Groups.get(id);
  if (!group) return undefined;

  const { seshers, watchers } = group.getMembers();

  return {
    group_id: group.id,
    member_count: group.members,
    name: group.name,
    state: group.state,
    visibility: group.visibility,
    persistent: group.persistent,
    sesh_counter: group.sesh_counter,
    watcher_count: watchers.length,
    sesher_count: seshers.length,
  };
}
