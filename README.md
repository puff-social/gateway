# puff.social Gateway

Elixir realtime gateway that enables realtime synchronization of group sessions on [puff.social](https://puff.social)

## Opcodes

| Code   | Name                     | Direction |
| ------ | ------------------------ | --------- |
| `0`    | Hello                    | `S > C`   |
| `1`    | Join Group               | `C > S`   |
| `2`    | Create Group             | `C > S`   |
| `3`    | Event                    | `S > C`   |
| `4`    | Send Device State        | `C > S`   |
| `5`    | Edit Group               | `C > S`   |
| `6`    | Update User              | `C > S`   |
| `7`    | Leave Group              | `C > S`   |
| `8`    | Inquire Group Heat       | `C > S`   |
| `9`    | Start with ready members | `C > S`   |
| `10`   | Disconnect device        | `C > S`   |
| `11`   | Send message to group    | `C > S`   |
| `12`   | End awaiting state       | `C > S`   |
| `13`   | Resume active session    | `C > S`   |
| `14`   | Send reaction to group   | `C > S`   |
| `15`   | Delete Group             | `C > S`   |
| `420`  | Heartbeat                | `C > S`   |

## Events (Op: 3)

| Event                          | Description                                                              |
| ------------------------------ | ------------------------------------------------------------------------ |
| `JOINED_GROUP`                 | Sent back once OP 1 succeeds                                             |
| `GROUP_CREATE`                 | Sent back once OP 2 succeeds                                             |
| `GROUP_DELETE`                 | Sent to group members when group deleted                                 |
| `GROUP_UPDATE`                 | Sent to group members when group is updated                              |
| `GROUP_USER_JOIN`              | Sent to other group members when a user joins                            |
| `GROUP_USER_LEFT`              | Sent to other group memebrs when a user leaves                           |
| `GROUP_USER_UPDATE`            | Sent to other group members when a users state updates                   |
| `GROUP_USER_DEVICE_UPDATE`     | Sent to other group members when a users device state updates            |
| `GROUP_JOIN_ERROR`             | Sent if OP 1 fails with a reason                                         |
| `GROUP_CREATE_ERROR`           | Sent if OP 2 fails with a reason                                         |
| `GROUP_START_HEATING`          | Sent to group members when heating cycle should begin                    |
| `GROUP_HEAT_INQUIRY`           | Sent to group members when OP 8 is sent                                  |
| `GROUP_USER_READY`             | Sent to group members when OP 4 contains a temp select state change      |
| `GROUP_USER_UNREADY`           | Sent to group members when a member disconnects a device or leaves group |
| `GROUP_VISIBILITY_CHANGE`      | Sent to group members when OP 5 contains a group visibility change       |
| `GROUP_ACTION_ERROR`           | Sent in response to any group action OP for errors with a code           |
| `USER_UPDATE_ERROR`            | Sent if OP 6 fails with a reason                                         |
| `PUBLIC_GROUPS_UPDATE`         | Sent to all socket clients when a group is made public or private        |
| `GROUP_USER_DEVICE_DISCONNECT` | Sent to group members when OP 10 is sent by another member               |
| `GROUP_REACTION`               | Sent to group members when OP 14 is sent by any member, with an emoji    |
| `GROUP_MESSAGE`                | Sent to group members when OP 11 is sent by any member                   |
| `SESSION_RESUMED`              | Sent in response to OP 13 when session is resumed successfully           |
