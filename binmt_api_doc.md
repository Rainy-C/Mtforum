# MT管理器论坛 (bbs.binmt.cc) 接口开发文档

> 基于 ProxyPin 抓包整理，适用于写第三方客户端
> 论坛系统：Discuz! X3 + comiis_app_portal（移动版门户插件）

---

## 一、基础配置

### 1. 服务器
- 主站：`https://bbs.binmt.cc`
- CDN：`https://cdn-bbs.mt2.cn`（头像、附件、图标）
- OSS：`https://oss3-bbs.mt2.cn`（帖子图片）
- Web服务器：openresty + HSTS 强制 HTTPS

### 2. 必带请求头
```
Cookie: cQWy_2132_auth=<你的auth值>; cQWy_2132_saltkey=<你的saltkey值>;
User-Agent: Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 Chrome/150.0 Mobile Safari/537.36
Referer: https://bbs.binmt.cc/forum.php
Accept-Encoding: gzip
```

### 3. 登录态 Cookie（关键！）
| Cookie名 | 作用 | 说明 |
|----------|------|------|
| `cQWy_2132_auth` | **登录认证令牌** | 最重要，相当于 token |
| `cQWy_2132_saltkey` | 安全密钥 | 配合 auth 使用 |
| `cQWy_2132_sid` | 会话ID | |
| `cQWy_2132_st_p` | 持久登录态 | 格式 `UID\|时间戳\|hash` |

> 只需 `auth` + `saltkey` 两个就能维持登录态。失效后重新抓包获取。

### 4. formhash（操作类接口必带）
- 当前值：`1a1ca082`
- 获取方式：从任意页面 HTML 中正则提取 `formhash = '([a-f0-9]+)'`
- 所有写操作（发帖、点赞、签到等）必须带此参数

### 5. 返回格式说明
- AJAX 接口（带 `inajax=1`）：返回 `text/xml`，结构为：
  ```xml
  <?xml version="1.0" encoding="utf-8"?>
  <root><![CDATA[ ...HTML片段... ]]></root>
  ```
  取 CDATA 内容，再用正则/解析器提取数据。
- 普通页面：返回 `text/html`，gzip 压缩（HTTP库会自动解压）
- 编码：全程 UTF-8

---

## 二、核心接口清单

### ① 帖子列表（AJAX，推荐用这个）
```
GET /plugin.php?id=comiis_app_portal&pid=1&page={页码}&comiis_list=yes&inajax=1
```
- 返回 XML，CDATA 内是帖子列表 HTML
- 每页约 15 条帖子
- **数据提取**：每条帖子是一个 `<li class="forumlist_li">`，包含：

| 字段 | 提取方式 | 示例 |
|------|----------|------|
| 帖子ID | `tid="(\d+)"` | 171315 |
| 作者UID | `uid=(\d+)` | 141274 |
| 作者名 | `uid=\d+[^>]*>([^<]+)` | SoloSu |
| 点赞数 | `num-all_\d+">(\d+)` | 7 |
| 点赞链接 | `action=recommend.*?tid=(\d+).*?hash=([a-f0-9]+)` | |

- 帖子详情URL：`forum.php?mod=viewthread&tid={tid}`

### ② 帖子导读页面（整页HTML）
```
GET /forum.php?mod=guide&view={类型}&index=1
```
| view 参数 | 含义 |
|-----------|------|
| `hot` | 热门帖子 |
| `newthread` | 最新帖子 |
| `digest` | 精华帖 |

### ③ 帖子详情页（两种URL等价）
```
# SEO友好URL（推荐，论坛实际用的就是这个）
GET /thread-{tid}-1-1.html

# 标准Discuz URL
GET /forum.php?mod=viewthread&tid={帖子ID}
```
- 翻页（多页帖子）：`thread-{tid}-{页码}-1.html` 或加 `&page={页码}`
- 返回完整 HTML，包含以下可提取数据：

| 字段 | 提取方式 | 示例 |
|------|----------|------|
| 标题 | `<title>(.*?)</title>` | 不要再狂欢了... - MT论坛 |
| 楼主名 | `top_user[^>]*>([^<]+)` | 帅比宝宝 |
| 版块ID | `forum-viewforum-fid-(\d+)` | 50 |
| formhash | `formhash\s*=\s*'([a-f0-9]+)'` | 1a1ca082 |
| **noticeauthor** | `noticeauthor[^>]*value="([^"]+)"` | f8d14rRlQ4KR/... |
| 帖子正文 | `class="comiis_message[^"]*"[^>]*>(.*?)</div>` | 每楼一层 |
| 楼层号 | `<sup>#</sup>` 前的数字 | 19 |

> ⚠️ **noticeauthor 是回复帖子的必需 token**，每个帖子页面不同，必须先 GET 帖子页提取，再用于回复 POST

### ③-1 查看指定楼层（AJAX）
```
POST /forum.php?mod=viewthread&tid={帖子ID}&viewpid={楼层ID}&mobile=2
```
- 请求体为空（Content-Length: 0）
- 返回 XML，CDATA 内是该楼层的完整 HTML
- 用于动态加载新回复（发回复后立即看到自己的楼层）

### ③-2 回复帖子（POST，写操作）
```
POST /forum.php?mod=post&action=reply&fid={版块ID}&tid={帖子ID}&extra=page%3D1&replysubmit=yes&mobile=2&handlekey=fastpost&loc=1&inajax=1
Content-Type: application/x-www-form-urlencoded; charset=UTF-8
```
**请求体（3个字段）：**
```
formhash={formhash}&noticeauthor={从帖子页提取的token}&message={回复内容URL编码}
```
**返回：**
```xml
<root><![CDATA[<p>非常感谢，回复发布成功，现在将转入主题页...</p>]]></root>
```
- 成功后响应里含新楼层 pid：`succeedhandle_fastpost('...&pid={新pid}&...')`
- **必须带 Referer 头**（帖子页URL）
- message 需要 URL 编码（UTF-8）

### ③-3 引用回复
```
POST /forum.php?mod=post&action=reply&fid={版块ID}&tid={帖子ID}&extra=page%3D1&repquote={被引用的pid}&replysubmit=yes&mobile=2&handlekey=fastpost&loc=1&inajax=1
```
- 比③-2多一个 `repquote={pid}` 参数，其余相同

### ④ 点赞（推荐）
```
GET /forum.php?mod=misc&action=recommend&handlekey=recommend_add&do=add&tid={帖子ID}&hash={formhash}
```
- 取消点赞：`do=sub`（推测）
- 需要 Referer 头

### ⑤ 版块列表/版块帖子
```
GET /forum.php?forumlist=1                          # 版块首页
GET /forum.php?mod=forumdisplay&fid={版块ID}        # 版块帖子列表
```

---

## 三、个人中心

### ⑥ 个人中心首页
```
GET /home.php?mod=space&do=profile&mycenter=1
```

### ⑦ 个人资料（含积分信息）
```
GET /home.php?mod=space&do=profile
```
- 返回HTML包含：积分、金币、贡献、威望、在线时间、注册时间等
- 你的 UID：**154205**

### ⑧ 我的帖子
```
GET /home.php?mod=space&do=thread&view=me
```

### ⑧-1 查看他人主页（带uid）
```
GET /home.php?mod=space&uid={用户UID}&do=profile
```

### ⑧-2 他人的帖子/回复/留言墙
```
GET /home.php?mod=space&uid={UID}&do=thread&view=me&type=thread&from=space   # 他发的主题
GET /home.php?mod=space&uid={UID}&do=thread&view=me&type=reply&from=space    # 他的回复
GET /home.php?mod=space&uid={UID}&do=wall&view=me&from=space                 # 留言墙
GET /home.php?mod=follow&do=follower&uid={UID}                                # 粉丝列表
```

### ⑧-3 私信系统
```
# 查看与某人的私信对话
GET /home.php?mod=space&do=pm&subop=view&touid={对方UID}

# 发送私信（POST）
POST /home.php?mod=spacecp&ac=pm&op=send&pmid=0&daterange=2&pmsubmit=yes&mobile=2
Content-Type: application/x-www-form-urlencoded
Body: formhash={hash}&touid={对方UID}&message={内容URL编码}
```

### ⑨ 我的收藏
```
GET /home.php?mod=space&do=favorite&view=me&type=all
```

### ⑩ 好友列表
```
GET /home.php?mod=space&do=friend
```

### ⑪ 检查新私信（轮询用）
```
GET /home.php?mod=spacecp&ac=pm&op=checknewpm&rand={时间戳}
```
- 空响应 = 没有新私信

---

## 四、签到系统（k_misign 插件）

### ⑫ 签到页面
```
GET /k_misign-sign.html
```

### ⑬ 今日签到排行（AJAX）
```
GET /plugin.php?id=k_misign:sign&operation=list&op={类型}
```
| op 参数 | 含义 |
|---------|------|
| `today` | 今日排行 |
| `month` | 本月排行 |
| `zong` | 总排行 |

- 返回HTML，每条签到记录包含：用户UID、用户名、签到时间、总天数、月天数、上次奖励金币数

### ⑭ 签到道具
```
GET /home.php?mod=magic&mid=k_misign:k_misign_bq&bid={bid}&inajax=1
```

---

## 五、积分商城（keke_integralmall 插件）

### ⑮ 商城商品页
```
GET /keke_integralmall-view.html?tid={商品ID}
```

### ⑯ 商城弹窗（兑换）
```
GET /plugin.php?id=keke_integralmall:show_win&tid={商品ID}&ac=km&formhash={formhash}&mobile=2
```

---

## 六、图片/附件

### ⑰ 图片代理（302重定向到CDN）
```
GET /forum.php?mod=image&aid={附件ID}&size={宽}x{高}&key={密钥}
```
- 返回 302，Location 头是真实CDN地址
- `size` 参数：`220x200`（缩略图）、`500x480`、`360x9999`（大图）
- **写软件时无需调此接口**，直接用帖子HTML里的图片URL即可

### ⑱ 用户头像
```
GET /uc_server/avatar.php?uid={用户UID}&size={small|middle}
```
- 301/302 重定向到 CDN 上的真实头像图
- 无头像时返回 `noavatar_middle.gif`

---

## ⚠️ 仍未抓到的接口

还差以下功能没操作到：
- **实际签到**（点击签到按钮的那个请求）—— 在签到页点"签到"
- **发新帖**（`forum.php?mod=post&action=newthread`）

---

## 八、搜索功能（完整3步流程）

### ⑲ 搜索发起（POST，返回302跳转）
```
POST /search.php?mod=forum
Content-Type: application/x-www-form-urlencoded
```
**请求体（4个字段）：**
```
formhash={formhash}&searchsubmit=yes&mod=forum&srchtxt={关键词URL编码}
```
**返回：** 302 跳转，`Location` 头含 `searchid`：
```
Location: search.php?mod=forum&searchid=1501&orderby=lastpost&ascdesc=desc&searchsubmit=yes&kw={关键词}&mobile=2
```
> ⚠️ 必须从 302 的 Location 头提取 `searchid`，下一步要用

### ⑳ 搜索结果页（GET，跟302跳转）
```
GET /search.php?mod=forum&searchid={searchid}&orderby=lastpost&ascdesc=desc&searchsubmit=yes&kw={关键词}&mobile=2
```
**返回：** 完整 HTML，包含搜索结果列表

**可提取数据：**

| 字段 | 提取方式 | 示例 |
|------|----------|------|
| 帖子tid | `thread-(\d+)-\d+-\d+\.html` | 171412 |
| 帖子标题 | thread链接后的文本 | 原生安卓\|MT论坛\|（改） |
| 作者uid | `uid=(\d+)` | 139562 |
| 作者名 | `uid=\d+[^>]*>([^<]+)` | 尘缘梦 |
| 版块 | `forum-viewforum-fid-(\d+).*?>([^<]+)` | 原生安卓 |
| 时间 | `(\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2})` | 2026-8-19 11:46 |
| 内容摘要 | 帖子标题后的文本片段 | 根据@466656897 的开源项目... |

**翻页：** 改 `page` 参数
```
GET /search.php?mod=forum&searchid={searchid}&orderby=lastpost&ascdesc=desc&searchsubmit=yes&kw={关键词}&page={页码}&mobile=2
```
- 本次搜索共 **18 页**结果

### 搜索完整流程代码
```python
import requests, re

session = requests.Session()
session.headers.update({
    'Cookie': 'cQWy_2132_auth=xxx; cQWy_2132_saltkey=xxx',
    'User-Agent': 'Mozilla/5.0 ...',
})

keyword = 'MT论坛'

# 步骤1: POST 发起搜索（禁止自动跳转，拿Location）
resp = session.post(
    'https://bbs.binmt.cc/search.php?mod=forum',
    data={'formhash': formhash, 'searchsubmit': 'yes', 'mod': 'forum', 'srchtxt': keyword},
    allow_redirects=False  # 关键！不自动跳转
)
# 从302的Location提取searchid
location = resp.headers['location']
searchid = re.search(r'searchid=(\d+)', location).group(1)

# 步骤2: GET 搜索结果页
result_url = f'https://bbs.binmt.cc/search.php?mod=forum&searchid={searchid}&orderby=lastpost&ascdesc=desc&searchsubmit=yes&kw={keyword}&mobile=2'
resp = session.get(result_url)

# 步骤3: 解析结果
tids = re.findall(r'thread-(\d+)-\d+-\d+\.html', resp.text)
print(f'搜索到 {len(set(tids))} 条结果')
```

---

## 九、账号登录（无需验证码！）

### ㉑ 获取登录页（提取 formhash + loginhash）
```
GET /member.php?mod=logging&action=login&mobile=2
```
从返回 HTML 提取两个值：
- `formhash`：`<input type="hidden" name="formhash" value='([a-f0-9]+)' />`
- `loginhash`：表单 action 里的 `loginhash=([A-Za-z0-9]+)`

### ㉒ 提交登录（POST）
```
POST /member.php?mod=logging&action=login&loginsubmit=yes&loginhash={loginhash}&handlekey=loginform&inajax=1
Content-Type: application/x-www-form-urlencoded; charset=UTF-8
```
**请求体（7个字段）：**
```
formhash={formhash}
&referer=https://bbs.binmt.cc/forum.php?mod=guide&view=hot&mobile=2
&fastloginfield=username
&cookietime=31104000
&username={用户名/手机号}
&password={密码}
&questionid=0
&answer=
```
**成功响应：**
```xml
<root><![CDATA[<p>手机号登录成功...</p>]]></root>
```
**关键：** 响应头 `Set-Cookie` 里会返回 `cQWy_2132_auth=...`，这就是登录凭证！
提取后保存即可维持登录态。

**失败响应示例：**
- 密码错误：`<p>密码错误或用户名非法...</p>`
- 用户不存在：`<p>用户名不存在...</p>`

---

## 七、写软件建议

### 推荐架构
```
1. 登录态：固定 Cookie（auth + saltkey），失效提示用户重新抓
2. 帖子列表：调 ① 帖子列表AJAX，正则提取帖子数据
3. 帖子详情：调 ③ thread-{tid}-1-1.html，解析HTML
4. 回复帖子：先 GET 帖子页提取 noticeauthor，再 POST ③-2
5. 点赞：调 ④，带 formhash
6. 签到：调 ⑫/⑬
7. 个人中心：调 ⑦
8. 私信：调 ⑧-3
```

### 回复帖子完整流程（最关键的写操作）
```python
import requests, re, urllib.parse

session = requests.Session()
session.headers.update({
    'Cookie': 'cQWy_2132_auth=xxx; cQWy_2132_saltkey=xxx',
    'User-Agent': 'Mozilla/5.0 (Linux; Android 16) ... Mobile Safari/537.36',
})

tid = 171409
fid = 50
thread_url = f'https://bbs.binmt.cc/thread-{tid}-1-1.html'

# 步骤1: GET 帖子页，提取 formhash + noticeauthor
resp = session.get(thread_url)
formhash = re.search(r"formhash\s*=\s*'([a-f0-9]+)'", resp.text).group(1)
noticeauthor = re.search(r'noticeauthor[^>]*value="([^"]+)"', resp.text).group(1)

# 步骤2: POST 回复
reply_url = f'https://bbs.binmt.cc/forum.php?mod=post&action=reply&fid={fid}&tid={tid}&extra=page%3D1&replysubmit=yes&mobile=2&handlekey=fastpost&loc=1&inajax=1'
data = {
    'formhash': formhash,
    'noticeauthor': noticeauthor,
    'message': '这是回复内容',
}
resp = session.post(reply_url, data=data, headers={
    'Referer': thread_url,
    'X-Requested-With': 'XMLHttpRequest',
})
# 成功返回: "回复发布成功"
if '成功' in resp.text:
    new_pid = re.search(r"pid=(\d+)", resp.text).group(1)
    print(f'回复成功，新楼层pid={new_pid}')
```

### 注意事项
- ⚠️ `formhash` 可能会变，建议每次启动时从首页提取一次
- ⚠️ 所有 AJAX 请求必须带 `X-Requested-With: XMLHttpRequest` 头
- ⚠️ 操作类请求（点赞/发帖/签到）必须带 `Referer` 头，否则可能被拒
- ⚠️ 返回内容是 HTML 片段不是 JSON，需要用正则或HTML解析器处理
- ✅ gzip 压缩由 HTTP 库自动处理，无需关心"乱码"
- ✅ 全站 HTTPS，无需处理证书问题（写软件时忽略证书校验或用系统信任）
