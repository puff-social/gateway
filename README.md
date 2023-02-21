# puff.social Gateway

Elixir realtime gateway that enables realtime synchronization of group sessions on [puff.social](https://puff.social)

## Opcodes

| Code   | Name                | Direction |
| ------ | ------------------- | --------- |
| `0`    | Hello               | `S > C`   |
| `1`    | Join Group          | `C > S`   |
| `2`    | Create Group        | `C > S`   |
| `3`    | Event               | `S > C`   |
| `4`    | Send Device State   | `C > S`   |
| `5`    | Edit Group          | `C > S`   |
| `6`    | Update User         | `C > S`   |
| `7`    | Leave Group         | `C > S`   |
| `8`    | Inquire Group Heat  | `C > S`   |
| `420`  | Heartbeat           | `C > S`   |

## Events (Op: 3)

| Event                      | Description                                                         |
| -------------------------- | ------------------------------------------------------------------- |
| `JOINED_GROUP`             | Sent back once OP 1 succeeds                                        |
| `GROUP_CREATE`             | Sent back once OP 2 succeeds                                        |
| `GROUP_DELETE`             | Sent to group members when group deleted                            |
| `GROUP_UPDATE`             | Sent to group members when group is updated                         |
| `GROUP_USER_JOIN`          | Sent to other group members when a user joins                       |
| `GROUP_USER_LEFT`          | Sent to other group memebrs when a user leaves                      |
| `GROUP_USER_DEVICE_UPDATE` | Sent to other group members when a users device state updates       |
| `GROUP_JOIN_ERROR`         | Sent if OP 1 fails with a reason                                    |
| `GROUP_START_HEATING`      | Sent to group members when heating cycle should begin               |
| `GROUP_HEAT_INQUIRY`       | Sent to group members when OP 8 is sent                             |
| `GROUP_USER_READY`         | Sent to group members when OP 4 contains a temp select state change |
| `GROUP_VISIBILITY_CHANGE`  | Sent to group members when OP 5 contains a group visibility change  |
| `PUBLIC_GROUPS_UPDATE`     | Sent to all socket clients when a group is made public or private   |
