import { Event, Op } from "@puff-social/commons";
import { Session } from "..";
import { Groups, Sessions } from "../../data";
import { resumeSession } from "../../validators/session";

interface Data {
  session_id: string;
  session_token: string;
}

export async function ResumeSession(this: Session, data: Data) {
  const validate = await resumeSession.parseAsync(data);
  if (!validate)
    return this.send(
      { op: Op.Event, event: Event.InternalError },
      { code: "INVALID_SESSION_RESUME_DATA" }
    );

  const session = Sessions.get(data.session_id);
  if (!session || data.session_token != session.token)
    return this.send(
      { op: Op.Event, event: Event.SessionResumeError },
      { code: "INVALID_SESSION" }
    );

  session.mobile = this.mobile;
  session.away = this.away;
  session.token = this.token;
  session.socket = this.socket;
  session.disconnected = false;

  session.send(
    { op: Op.Event, event: Event.SessionResumed },
    { session_id: session.id }
  );

  Sessions.delete(this.id);

  session.startAliveTimer();

  if (!this.group_id) return;
  const group = Groups.get(this.group_id);
  group?.broadcast(
    { op: Op.Event, event: Event.GroupUserUpdate },
    {
      group_id: group.id,
      session_id: this.id,
      disconnected: session.disconnected,
    }
  );
}
