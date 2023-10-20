import { Server } from "ws";
import Route from "route-parser";
import { users } from "@prisma/client";
import { Event, Op, VoiceChannelState } from "@puff-social/commons";
import fastify, { FastifyRequest } from "fastify";
import { IncomingMessage, ServerResponse, createServer } from "http";

import { env } from "./env";
import { Session } from "./session";
import {
  Groups,
  Sessions,
  getGroup,
  getSessionsByUserId,
  publicGroups,
} from "./data";

const internal = fastify();
const server = createServer();
const wss = new Server({ server });

wss.on("connection", (socket) => {
  const session = new Session(socket);
  Sessions.set(session.id, session);

  console.log("Got new socket connection", session.id);

  socket.on("close", (code, reason) => {
    console.log(
      `Socket session was closed attached to session ${session.id} ( ${code} - ${reason} )`
    );
    session.disconnected = true;

    if (session.group_id) {
      const group = Groups.get(session.group_id);

      if (group)
        group?.broadcast(
          { op: Op.Event, event: Event.GroupUserUpdate },
          {
            group_id: group.id,
            session_id: session.id,
            disconnected: session.disconnected,
          }
        );
    }
  });

  const timeout = setTimeout(() => {
    if (!session || !session.socket) return clearTimeout(timeout);

    console.log(
      `DEBUG: Checking state of session ${session.id} - State: ${session.socket.readyState} - last hb: ${session.last_heartbeat}`
    );

    if (session.socket.readyState != session.socket.OPEN) {
      session.close();
      Sessions.delete(session.id);
      clearTimeout(timeout);
    }
  }, 10 * 1000);
});

const methods = [
  {
    method: "GET",
    route: new Route("/health"),
    handler: (
      req: IncomingMessage,
      res: ServerResponse<IncomingMessage>,
      url: URL,
      route: Route
    ) => {
      res.writeHead(204, "OK", {
        "access-control-allow-origin": "*",
      });
      res.end();
    },
  },
  {
    method: "GET",
    route: new Route("/v1/groups"),
    handler: (
      req: IncomingMessage,
      res: ServerResponse<IncomingMessage>,
      url: URL,
      route: Route
    ) => {
      res.writeHead(200, "OK", {
        "content-type": "application/json",
        "access-control-allow-origin": "*",
      });
      res.write(JSON.stringify({ success: true, data: publicGroups() }));
      res.end();
    },
  },
  {
    method: "GET",
    route: new Route("/v1/groups/:id"),
    handler: (
      req: IncomingMessage,
      res: ServerResponse<IncomingMessage>,
      url: URL,
      route: Route
    ) => {
      res.writeHead(200, "OK", {
        "content-type": "application/json",
        "access-control-allow-origin": "*",
      });
      res.write(
        JSON.stringify({
          success: true,
          data: getGroup((route.match(url.pathname) as { id: string }).id),
        })
      );
      res.end();
    },
  },
];

server.on(
  "request",
  (req: IncomingMessage, res: ServerResponse<IncomingMessage>) => {
    const url = new URL((req.url as string) || "/", "http://localhost");

    const route = methods?.find(
      (route) =>
        route.route &&
        route.route.match(
          url.pathname.endsWith("/") && url.pathname.length > 1
            ? url.pathname.slice(0, -1)
            : url.pathname
        ) &&
        route.method == req.method
    );

    if (!route) {
      res.writeHead(404, "Not Found", {
        "content-type": "application/json",
        "access-control-allow-origin": "*",
      });
      res.write(JSON.stringify({ code: "not_found" }));
      res.end();
      return;
    }

    route.handler(req, res, url, route.route);
  }
);

server.listen({ port: env.PORT, host: "0.0.0.0" }, () => {
  console.log(`GW > Listening on ${env.PORT}`);
});

internal.post(
  "/user/:id/update",
  async (
    req: FastifyRequest<{
      Params: { id: string };
      Body: { user: users; voice: VoiceChannelState };
    }>,
    res
  ) => {
    const sessions = getSessionsByUserId(req.params.id);
    if (sessions.length == 0) return res.status(200).send("no");

    for (const session of sessions) {
      if (req.body.user === null || req.body.user) session.user = req.body.user;
      if (req.body.voice === null || req.body.voice)
        session.voice = req.body.voice;
      session.updateUser();
    }

    return res.status(204).send();
  }
);

internal.listen({ port: env.INTERNAL_PORT, host: "0.0.0.0" }, () => {
  console.log(`GW > Internally listening on ${env.PORT}`);
});
