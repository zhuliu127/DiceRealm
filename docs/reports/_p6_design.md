# P6 局域网传输层 · 设计文档

**编制**：2026-11-09
**状态**：代码已落地并全绿（1336 组），真机联调待验证
**对应实现**：`lib/net/` 6 个文件 + `lib/ui/room/` 3 个文件

---

## 1. 一句话架构

> **局域网不是另一条链路，只是地址从哪来的问题。**

这是旧版 `room-lan.js` 注释里的原话，也是 P6 全部设计的出发点。落地方式：
`RoomSession` 抽象在 P5 就留好了（`LocalLoopbackSession` 是第一个实现），
P6 只是补第二个实现（`RemoteSession`）——**UI 层零改动就知道自己在网上说话了**。

---

## 2. 分层与职责边界

| 层 | 文件 | 职责 | 明确不做 |
|---|---|---|---|
| 协议 | `net/room_frame.dart` | 7 种帧的编解码、版本兼容 | 不做裁剪、不做鉴权 |
| 服务端 | `net/lan_server.dart` | HTTP + WebSocket 同端口、`SendPlan` 分发、座位分配 | 不做业务判断 |
| 客户端 | `net/lan_client.dart` | 连接、重连、发送队列、gap 自愈 | 不做裁剪 |
| 发现 | `net/lan_discovery.dart` | UDP 4210 广播/扫描 | 不做决策 |
| 地址 | `net/room_endpoint.dart` | 规范化 + 多 base 候选排序 | 不做探测 |
| 编排 | `net/lan_room_host.dart` | 服务 + 广播的生命周期 | 不做 UI |
| 会话 | `ui/room/room_session_remote.dart` | `RoomSession` 的远端实现 | 不做 I/O |
| 会话 | `ui/room/room_session_hosting.dart` | KP 双投递（本机 + 网络） | 不做决策 |
| 工厂 | `ui/room/room_net_factory.dart` | 建房/加入/附近的一次性入口 | — |

**关键边界**：`plan()` 是唯一的裁剪点。传输层只搬运它的产物（`SendPlan.toJson()`），
再判一次只会产生第二套真相。

---

## 3. 帧协议

7 种帧，刻意做小：

| 帧 | 方向 | 载荷 |
|---|---|---|
| `hello` | C→S | `code` / `seat`（可空=请分配）/ `role` / `nickname` |
| `joined` | S→C | `seat` / `code` / `role` / `lastSeq` |
| `plan` | S→C | `to` + `msg`（`SendPlan.toJson()` 原样） |
| `intent` | C→S | `op` + `p` |
| `act` | C→S | 外层 `op='act'`，内层 `p.op` 是 action 名 |
| `sync` | C→S | `lastSeq`（请求补拉） |
| `bye` / `error` | 双向 | 断开 / 错误码（**不夹带**任何房间状态） |

**版本策略**：`v` 不匹配直接拒绝，缺 `v` 视为兼容（不踢旧客户端）。

**扁平设计**：帧是 `{v, k, ...data}` 而不是嵌套 `{k, p:{...}}`——
旧版层层嵌套，排查时得多点两次才看得到内容。

---

## 4. 服务端

### 4.1 HTTP 路由（同端口 4211）

| 路径 | 用途 |
|---|---|
| `GET /health` | 房间摘要（房号/状态/人数/seq） |
| `GET /state?seat=p1` | 按座位裁剪后的全量（断线补拉用） |
| `WS /ws` | 升级为 WebSocket |

### 4.2 连接生命周期

```
WS 升级 → 等 hello → 校验房号 → 分配/校验座位 → 回 joined
        → 立刻补一帧 plan(sync)  ← 客户端不用再单独请求
        → 进入转发循环
```

**为什么补 sync 而不是让客户端请求**：省一次往返，且避免「joined 到了但首屏空白」的中间态。

### 4.3 座位分配

- `seat` 为空 → 找第一个空闲座位（玩家 `p1..p6` / 旁观 `sp1..sp4`）→ `attachPeer` 进花名册
- `seat` 指定但不在花名册 → 拒 `UNKNOWN_SEAT`（**不能凭空造座位**，P4 是权威）
- 满 → `ROOM_FULL`

**两族座位分开找，绝不混用**。旁观者裁剪更狠（看不到别人手绘板、私有素材），
分错族等于给了错权限。

**判断依据是花名册而不是连接表**：`attachPeer` 一执行座位就进花名册，
花名册才是「这个座位有人了」的唯一真相。

---

## 5. 客户端

### 5.1 重连

指数退避 `[500, 1000, 2000, 4000, 8000]` ms，封顶 8 秒。

**重连成功后必补一次全量**——断线期间漏掉的事件不能靠增量补回来。

### 5.2 gap 自愈

`receive()` 返回 `gap:true` → 立刻发 `sync` → 链接状态转 `resync`。
这条链路和本机环回一模一样（`LocalLoopbackSession._deliver` 也是这么做的）。

### 5.3 座位变更

服务端可能分配到不同座位（客户端发空 seat 时）。`joined` 回来后：
- 更新 `seat`
- **重建 `RoomClient`** —— 裁剪口径是按 seat 算的，用旧座位接收会看到别人的数据或什么都看不到

---

## 6. 发现与地址

### 6.1 UDP 广播（4210）

- 服务端每 1 秒广播一次摘要（`RoomAnnounce`）
- 扫描方 `Future.any([delay(timeout), done])` 保证到点必返回、必不抛
- 同 `code` 覆盖（人数会变），不是追加

**摘要只带公开字段**：房号 / 房名 / KP名 / 人数 / 状态 / 地址 / `wifi`。
广播是明文的，**绝不带宽成员明细、场景、日志**。

### 6.2 `wifi: false` 的含义

服务端只拿到回环地址 ⇒ 这间房**只有自己能进**，邀请链接对同伴是死路。

**必须在建房之前提示**，而不是让用户拿两台手机试半天。
旧版 v1.18.4 修过这个，Dart 侧换个形式又踩了一遍：

`resolveIp()` 不能「拿到第一个非回环 IPv4 就用」——
装了 Clash/VPN 的机器上会先拿到 **198.18.0.1**（RFC 2544 基准段，TUN 虚拟网卡）。
现在按网段打分：

| 网段 | 分 |
|---|---|
| `169.254.*` | 0（链路本地） |
| `198.18.*` / `198.19.*` | 0（基准测试段，VPN TUN） |
| `192.168.*` | 100 |
| `10.*` | 90 |
| `172.16–31.*` | 80 |
| 其它 | 10 |

拿不到真私网就**留空**（base 退回 `127.0.0.1` + `wifi:false`），
让界面如实说「只有你自己能进」，而不是假装连上了。

### 6.3 多 base 候选

顺序：**注入的 > 用户手填 > 内置预设**，去重。

注入的必须排第一——它代表「这台手机现在就是服务器」，
用户设置里那个旧地址不该盖过它。

为什么不能简化成「一个 base 变量」：
- 一台手机可能同时有 WiFi + 热点 + VPN，只有一个能通
- 用户可能手填 `192.168.1.7`（没写 `http://`）或带尾斜杠
- 注入地址不能被用户设置盖掉

简化了就是「局域网时通时不通」，而且极难复现。

---

## 7. 会话层

### 7.1 三个实现的关系

```
RoomSession (抽象)
  ├── LocalLoopbackSession   本机全内存（P5），KP + 本机派生的玩家/旁观视角
  ├── HostingLocalSession    继承上一个，pumpPlans 时多投一遍到网络（KP 建房）
  └── RemoteSession          远端视角（玩家/旁观加入）
```

### 7.2 RemoteSession 的三处刻意差异

| 项 | 行为 | 原因 |
|---|---|---|
| `hostRead` | 恒 null | 玩家/旁观没有权威只读面（拿不到就是拿不到） |
| `exportSave` / `importSave` | null / no-op | 存档是 KP 的事 |
| `rollback` | 返回「没回退」的结果，不抛 | UI 永不提供回退入口（K1），但诊断路径不该把页面打崩 |

### 7.3 双投递的顺序

`HostingLocalSession.pumpPlans`：
```dart
super.pumpPlans(plans);   // 先本机
server.pump(plans);       // 再网络
```

**先本机**：保证单机玩法永不因网络问题退化。

---

## 8. UI 接线

### 8.1 `_RoomShell` 的入参拆分

原来吃 `RoomBoot`（含非空的 `host` / `hub`），远端没有这两个。
改成「它真正需要的四样」：`session`（抽象）/ `local` / `controller` / `onClose`。

收益：
- `RoomBoot` 一个字段都没改（10+ 处测试零改动）
- UI 层从此**不知道自己在本机还是网络上**

### 8.2 产品行为

| 操作 | 行为 |
|---|---|
| 建房 | 起服务 + 广播；横幅如实报「局域网已开（地址）」或「未连局域网（只有你自己能进）」 |
| 加入 | 扫 1.2s 局域网 → 找到就连；没找到回退「本机预览」并明示 |

**不骗用户**是硬要求：连不上就说连不上，不能用「已连接」糊过去。

### 8.3 退房清理

`RoomBoot.dispose()` = `local.dispose()` + `session.dispose()`。

**session 必须 dispose**：`HostingLocalSession` 持有局域网服务，
只清 local 会留下幽灵房（别人一直能搜到一间没人管的房）。

### 8.4 两个排障入口（`_p6_design` 初版遗漏，本批补上）

局域网一旦连不上，用户能看到的只有「对方没反应」。旧版 `room-ui.js` 有三个
排障弹层（`lanCheckSheet` / `selfCheckSheet` / `noWifiSheet`），P6 初版全漏了。

#### 局域网自检 `sheets/sheet_lan_check.dart` + `net/lan_diagnose.dart`

核心不是「报个错」，而是**把「连不上」拆成几个可行动的原因**：

| verdict | 含义 | 用户该做什么 |
|---|---|---|
| `lanOk` | 局域网地址可达 | 把地址发给同伴 |
| `lanDown` | 本机没起服务 | 先去建房 |
| `lanBlocked` | **回环通、局域网地址不通** | 查 AP 隔离 / 访客网络 / 防火墙 / 选错网卡 |
| `lanTimeout` | 两探都超时 | 关防火墙、换 WiFi |
| `lanDead` | 两探都失败 | 服务崩了或端口被占，重建房 |

**判读顺序有讲究**：`loopOk` 必须先于 `anyTimeout` 判断。
「服务活着但地址不通」比「某一探超时」是更确凿的信息 ——
顺序反了会把「AP 隔离」误报成「防火墙丢包」，处置方向就错了。
这条抽成了纯函数 `judge(lanOk, loopOk, anyTimeout)`，可脱离真网络单测。

**比旧版多一件事**：列出所有网卡并打分（浏览器里拿不到）。
这直接解决「选错网卡」这个最难自查的问题 —— Clash/VPN 的 TUN 网卡
（`198.18.x`）会让服务「启动成功、界面显示已连接，但同伴永远连不上」。

> ⚠️ 实现坑：`_swapHost` 必须用 `replaceFirstMapped`。Dart 的 `replaceFirst`
> **不认** JS 的 `$1` 捕获组语法，会拼出 `http://$1127.0.0.1:4211` 这种废 URL，
> 于是回环探测永远失败，`lanBlocked` 这条最有价值的判读永远走不到。

#### 附近的房间 `sheets/sheet_nearby_rooms.dart`

UDP 扫描结果列表（旧版 `room-ui.js:1604`）。价值是**用户不必先知道房号**。
选中后自动填好房号与地址并直接加入 —— 用户点「加入」已经表达了「就是这间」，
再让他抄 6 位房号是多余的。

空态必须给排查清单（同一 WiFi / KP 已建房 / AP 隔离 / 手输兜底），
不能只写「没找到」。

---

## 9. 测试策略

### 9.1 真 socket，不 mock

传输层最容易出的问题是「编译过、跑不通」（握手时序、端口、帧版本），
这些只有真跑才能抓到。所以 `p6_lan_*` 系列全部真开 `HttpServer`、真连 WebSocket。

UDP 测试用 `127.0.0.1` 单播代替广播——广播在防火墙/容器下常收不到，会造假红。

### 9.2 UI 测试必须关网络（**最重要的一条**）

`testWidgets` 跑在 FakeAsync 下，**推不动真实的 socket bind**。
于是 `await bootHostedRoom(...)` 永远不返回，页面进不去
（表现是「找不到大厅页」，看起来完全像 UI bug）。

三个开关（`RoomNetFactory` 静态字段）：

| 开关 | 测试值 | 作用 |
|---|---|---|
| `discoveryEnabled` | `false` | 不跑真 UDP 扫描（省 1.2s/用例，且不受防火墙影响） |
| `networkEnabled` | `false` | 不 bind、不广播；`HostingLocalSession` 仍构造，`pump` 变 no-op |
| `servicePortOverride` | `0` | 端口由系统分配，不抢 4211 |

`setUp` 里关、`tearDown` 里复原。

**教训**：硬跑真 I/O 会得到「看起来像业务 bug 的环境 bug」，排查成本极高。

### 9.3 测试矩阵

| 文件 | 条数 | 覆盖 |
|---|---|---|
| `p6_lan_transport_test.dart` | 7 | 帧编解码 / 握手 / 收发 / 座位校验 / 同 seat 重连 |
| `p6_lan_discovery_test.dart` | 12 | 地址工具 8 + 摘要 2 + 真 UDP 3（含超时/去重） |
| `p6_lan_room_host_test.dart` | 4 | 生命周期 / 幽灵房 / 幂等 / 端口占用 |
| `p6_room_net_factory_test.dart` | 8 | 端到端闭环 / 连接态 / 座位分配 / 旁观入座 / 无网降级 |

---

## 10. 已知约束与红线

| 项 | 说明 |
|---|---|
| **K3** | 中继**禁止**直接序列化 `LogRecord.toWireJson()`（含明文 `p`）。只用 `SendPlan.toJson()`（`plan()` 已裁剪的出站信封） |
| 明文广播 | 摘要必须是纯公开字段；同网段任何人可收 |
| 单机降级 | 服务起不来不阻止开团（端口占用 / 没连 WiFi），只是要如实提示 |
| 旁观容量 | `sp1..sp4`（4 人）；玩家 `p1..p6`（6 人） |
| 不做的事 | 公网中继、断线后的事件补偿窗口（当前只补全量）、加密 |

---

## 11. 待验证

**自动化能做的已经做完**：全量 1475 组 0 红、两道静态门禁全过、
模拟器上真 Android 服务端 + 外部客户端全链路跑通（`_p6_emulator_verify.txt`）。

**剩下的只能真机验**，清单见 `_manual_test_checklist.md`，要点：
- Android 上的 UDP 广播是否真的能跨设备收（部分机型/路由器会拦）
- 多播锁已实现：`CHANGE_WIFI_MULTICAST_STATE` 权限与运行时
  `MulticastLock` 的申请 / 释放都在 P6 落地，真机只需确认 ROM 是否放行；
  兜底仍是手输服务地址，一定可用
- 真实网络抖动下的重连体验
