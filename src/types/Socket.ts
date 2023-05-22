export interface SocketMessage<T = any> {
  op: number;
  t?: string;
  d?: T;
}
