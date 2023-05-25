import { Session } from "..";

export async function Heartbeat(this: Session) {
  this.last_heartbeat = new Date();
}
