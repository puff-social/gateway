import { envsafe, port, str } from "envsafe";

export const env = envsafe({
  PORT: port({
    default: 9000,
  }),
  METRICS_PORT: port({
    default: 9001,
  }),
  INTERNAL_PORT: port({
    default: 9002,
  }),
  INTERNAL_API: str({
    default: "http://puffsocial-api:8002",
    devDefault: "http://127.0.0.1:8002",
  }),
});
