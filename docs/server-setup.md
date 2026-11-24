# 服务器部署说明

应用本身**不需要服务器**也能用：本机开房、局域网开房、单人试玩全部离线可用。

只有这两种场景需要服务器：

| 场景 | 需要的服务 | 客户端配置项 | 形如 |
|---|---|---|---|
| 把角色卡分享成链接给朋友看 | **分享服务** | 设置 → 服务地址 → 分享 | `https://你的域名/coc` |
| 异地玩家用房间号加入同一局 | **房间中继服务** | 设置 → 服务地址 → 房间 | `https://你的域名/room` |

两项都填在 **设置 → 服务地址**，留空即关闭对应功能。填完后立刻生效，不需要重启。

> 本文只描述**客户端要求服务端长什么样**（接口契约），不提供完整服务端实现。
> 你可以用任意语言/框架实现，只要满足下面的端点与字段。

---

## 一、分享服务

### 接口契约

客户端只用到两个端点，`{base}` 即 `shareBase`（例如 `https://你的域名/coc`）：

**1. 创建分享**

```
POST {base}/api/cards
Content-Type: application/json

{
  "name": "角色卡名称",
  "visibility": "public" | "unlisted",
  "data": { ... 角色卡 JSON ... }
}

→ 200 {"id": "<分享 ID>", ...}
```

**2. 删除分享**

```
POST {base}/api/cards/<id>/del
Content-Type: application/json

{"token": "<创建时返回的删除令牌>"}

→ 200 {"ok": true}
```

要点：

- `id` 由服务端生成，客户端会把它拼进可访问链接
- 删除必须校验 `token`，否则任何人都能删别人的卡
- `visibility=public` 表示可被索引/列出，`unlisted` 表示只有拿到链接才能看
- 建议限制单卡体积（角色卡含头像 base64 时通常几十 KB 到几百 KB）

### 部署要点

1. 一个静态页面 + 上面的两个接口即可，用来渲染分享卡
2. 建议加**速率限制**与**内容长度上限**（例如单请求 2 MB）
3. 若与中继服务同域，注意把 `/coc` 与 `/room` 用不同 location 分开代理

---

## 二、房间中继服务

用于「公网开房」：KP 建房拿到 6 位房间号，异地玩家输入房间号加入。中继只做转发，房间状态由 KP 端权威持有。

### 接口契约

`{base}` 即 `roomBase`（例如 `https://你的域名/room`）。

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/health` | 健康检查，返回 `{"ok": true, ...}` |
| POST | `/api/rooms` | 建房，返回 `{code, hostToken, wsBase}` |
| POST | `/api/rooms/<code>/join` | 加入，body 含昵称/设备标识，返回 `{code, mtoken, wsUrl, role, ...}` |
| POST | `/api/rooms/<code>/resume` | KP 续玩（需 `hostToken`），恢复 SUSPENDED/RECRUITING/IN_GAME 房间 |
| POST | `/api/rooms/<code>/backup` | 上传全量存档（**仅 hostToken**），body `{seq, payload}` |
| POST | `/api/rooms/<code>/backup/read` | 读取全量存档（**仅 hostToken**） |
| GET(WS) | `/ws` | 实时通道；握手时带房间号与令牌 |

### 关键约束（客户端就是这么用的）

1. **房间号必须小写**：服务端正则建议 `[a-z0-9]{4,12}`。客户端 UI 显示会转大写，但向服务端请求时会转小写 —— 服务端若按大写匹配，公网加入会 404。
2. **`hostToken` 是唯一的管理凭据**：建房时返回，之后续玩、上传/读取全量存档都靠它。**绝不能**用「设备 ID」之类的弱凭据替代，否则任何已加入的玩家都能拉走全量存档。
3. **全量存档走 POST body**，不要把令牌放进查询串（会进 nginx access log）。
4. **WebSocket 路径 `/ws`**，不要额外加前缀；如果反向代理会 rewrite 前缀，务必保证服务端看到的路径仍是 `/ws`。
5. 客户端与服务器之间只走 **HTTPS/WSS**；`http://` 的地址会被判成局域网而不是公网。

### 房间生命周期建议

| 状态 | 回收策略 |
|---|---|
| 普通房间无活跃 | 6 小时 |
| `CLOSED`（已结束） | 6 小时 |
| `SUSPENDED`（KP 主动挂起） | 30 天 |
| 有云端备份的房间 | 至少 30 天 |

### 参考部署

```nginx
# 分享服务
location ^~ /coc/ {
    proxy_pass http://127.0.0.1:12700/;
    client_max_body_size 8m;
}

# 房间中继
location ^~ /room/ {
    proxy_pass http://127.0.0.1:12710/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 600s;
    client_max_body_size 64m;   # 要大于服务端自身的存档上限
}
```

```ini
# /etc/systemd/system/coc-room.service
[Unit]
Description=Dice Realm room relay
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/coc-room/room_server.py
Restart=always
User=www-data

[Install]
WantedBy=multi-user.target
```

要点：

- `client_max_body_size` 必须**大于**服务端自己的存档上限（客户端上传的全量存档可能几十 MB）
- WebSocket 需要 `Upgrade` / `Connection` 透传，否则连上就断
- 中继监听 `127.0.0.1`，只让 nginx 反代，不要直接暴露端口
- 健康检查：`curl https://你的域名/room/health` 应返回 `{"ok": true}`

---

## 三、安全清单

公开部署前建议逐条过一遍：

- [ ] 全站 HTTPS，证书自动续期
- [ ] 中继只监听回环地址，由反向代理对外
- [ ] `hostToken`、`mtoken` 由服务端用密码学随机数生成，长度 ≥ 32 字符
- [ ] 存档接口只接受 `hostToken`，并校验房间归属
- [ ] 令牌不写日志（检查 nginx access log 与业务日志）
- [ ] 单请求体积上限、房间创建速率限制
- [ ] 定期备份数据库（SQLite 建议用 `.backup()` 而不是直接拷活库）
- [ ] 明确数据保留策略，并在分享页/房间页给用户一句说明

---

## 四、自检

配好之后按这个顺序验证：

1. `curl https://你的域名/room/health` → `{"ok": true}`
2. App → 设置 → 服务地址 → 填入 `https://你的域名/room` → 保存
3. App → 首页 → 跑团房间 → 选规则 → **开公网房间** → 拿到房间号
4. 第二台设备 → 加入房间 → 输入房间号（**服务地址也要填**，加入逻辑读输入框而不是设置里那项）→ 能进且成员数变 1
5. 断网重连一次，确认回到原座位而不是变成新人

> 第 4 步的括号是实测过的坑：**加入房间时的中继地址读的是「加入」区域的输入框**，
> 设置页里那项只用于「开公网房间」。两台设备都填一次最稳。
