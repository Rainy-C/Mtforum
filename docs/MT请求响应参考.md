
# MT论坛 帖子请求/响应 全流程总结

---

## 一、帖子列表

### 请求
```
GET https://bbs.binmt.cc/plugin.php?id=comiis_app_portal&pid=1&page=1&comiis_list=yes&inajax=1
```
| 参数 | 值 | 说明 |
|------|-----|------|
| id | comiis_app_portal | comiis门户插件 |
| pid | 1 | 频道ID |
| page | 1/2/3... | 页码 |
| comiis_list | yes | 列表模式 |
| inajax | 1 | AJAX模式 |

**必带头**：`X-Requested-With: XMLHttpRequest` + `Cookie`(登录态)

### 响应
```xml
<?xml version="1.0" encoding="utf-8"?>
<root><![CDATA[
  <li class="forumlist_li">
    <!-- 作者区 -->
    <a href="home.php?mod=space&uid=157080" class="top_user">ZhaoMods</a>
    <span class="top_lev">Lv.4</span>
    <span class="f_d">前天 09:43</span>
    <a href="forum-44-1.html">来自 综合交流</a>
    <!-- 标题+摘要 -->
    <h2><a href="thread-171255-1-1.html">123云盘3.2.16完美脱修</a></h2>
    <div class="list_body"><a href="...">完美脱修，减到70mb...隐藏的是小飞机云盘</a></div>
    <!-- 缩略图 -->
    <div class="comiis_pyqlist_imgs"><ul>
      <li><img src="forum.php?mod=image&aid=371057&size=220x200&key=xxx"></li>
    </ul></div>
    <!-- 统计 -->
    <div class="comiis_znalist_bottom">
      <li>1384阅读</li>
      <li>199评论</li>
      <li><span class="num-all_171255">14</span>赞</li>
    </div>
  </li>
]]></root>
```

**提取要点**：
- tid → `thread-(\d+)-` 
- 标题 → `.mmlist_li_box h2 a` 的文本
- 摘要 → `.list_body a` 的文本
- 作者uid → `top_user` 链接里的 `uid=(\d+)`
- 阅读量 → `(\d+)阅读`
- 评论量 → `(\d+)评论`
- 赞 → `num-all_\d+">(\d+)`

---

## 二、帖子详情

### 请求
```
GET https://bbs.binmt.cc/thread-{tid}-1-1.html
# 翻页: thread-{tid}-{page}-1.html
```

### 响应（HTML页面）

```html
<!-- 全局变量 -->
<script>
var formhash = '1a1ca082';        ← 写操作必需
var discuz_uid = '154205';        ← 当前用户UID
</script>

<!-- 每个楼层: <div id="pidXXX"> -->
<div id="pid11640673">
  <!-- 作者 -->
  <a class="top_user">ZhaoMods</a>
  <a class="top_lev">Lv.4 高中生</a>
  <img class="top_tximg" src="uc_server/avatar.php?uid=157080">
  
  <!-- 楼层标识 -->
  <span class="f_d y">沙发</span>  ← 楼主/沙发/板凳/地板/5#
  
  <!-- 时间 -->
  <span class="kmtime">前天 09:43</span>
  
  <!-- 正文 -->
  <div class="comiis_a comiis_message_table cl">
    <script>replyreload += ',' + 11640673;</script>  ← 需移除
    <i class="pstatus">本帖最后由...编辑</i>          ← 需移除
    
    1.去除登录<br>
    <strong>完美脱修</strong>如图                    ← 加粗
    
    <!-- 帖子附图 -->
    <span class="comiis_postimg">
      <img src="https://oss3-bbs.mt2.cn/forum/202608/17/xxx.jpg">
    </span>
    
    <!-- 代码块 -->
    <div class="comiis_blockcode"><ol><li>https://pan.xxx</li></ol></div>
    
    <!-- 隐藏内容提示 -->
    <div class="comiis_quote">
      Cynnie，如果您要查看本帖隐藏内容请<a>回复</a>
    </div>
  </div>
  
  <!-- 赞赏区 -->
  <div class="comiis_rate">3人打赏, 3好评</div>  ← 需移除
  
  <!-- 回复按钮(含引用参数) -->
  <a href="forum.php?mod=post&action=reply&fid=44&tid=171255&repquote=11640673">
    回复
  </a>
</div>

<!-- 快速回复表单 -->
<form id="fastpostform">
  <input name="formhash" value="1a1ca082">
  <input name="noticeauthor" value="eef5B0ljqn52...">  ← 回复必需token
  <textarea name="message"></textarea>
</form>
```

**提取要点**：
| 字段 | 提取方式 |
|------|----------|
| formhash | `formhash\s*=\s*'([a-f0-9]+)'` |
| noticeauthor | `noticeauthor[^>]*value="([^"]+)"` |
| fid | `forum-viewforum-fid-(\d+)` |
| 楼层内容 | `div[id^="pid"]` → `.comiis_message_table` |
| 帖子图片 | `.comiis_postimg img` 的 src |
| 隐藏提示 | `.comiis_quote` 的文本 |
| 楼主判断 | 第1页第1个 `div[id^="pid"]` |
| 引用回复pid | 回复链接里的 `repquote=(\d+)` |

---

## 三、回复帖子

### 请求
```
POST https://bbs.binmt.cc/forum.php?mod=post&action=reply&fid={fid}&tid={tid}&extra=page%3D1&replysubmit=yes&mobile=2&handlekey=fastpost&loc=1&inajax=1

Content-Type: application/x-www-form-urlencoded; charset=UTF-8
Referer: https://bbs.binmt.cc/thread-{tid}-1-1.html
X-Requested-With: XMLHttpRequest

# Body:
formhash={formhash}&noticeauthor={从详情页提取}&message={回复内容URL编码}

# 引用回复加参数 repquote={被引用pid}
```

### 响应
```xml
<!-- 成功 -->
<root><![CDATA[
  <p>非常感谢，回复发布成功，现在将转入主题页...</p>
  succeedhandle_fastpost('...&pid=11655873&...', '回复发布成功', {...})
]]></root>

<!-- 失败 -->
<root><![CDATA[<p>您还未登录，不能回复</p>]]></root>
```

**判断**：`body.contains('成功')` 或 `body.contains('succeedhandle')`

---

## 四、点赞

### 请求
```
GET https://bbs.binmt.cc/forum.php?mod=misc&action=recommend&handlekey=recommend_add&do=add&tid={tid}&hash={formhash}
Referer: https://bbs.binmt.cc/thread-{tid}-1-1.html
```
- 取消点赞：`do=sub`

### 响应
```xml
<root><![CDATA[
  'recommendv':'+1','recommendc':'5','daycount':'9'
]]></root>
```
返回更新后的点赞数。

---

## 五、搜索（3步流程）

### 步骤1：POST 发起搜索
```
POST https://bbs.binmt.cc/search.php?mod=forum
Content-Type: application/x-www-form-urlencoded

formhash={hash}&searchsubmit=yes&mod=forum&srchtxt={关键词}
```

### 响应1：302重定向
```
HTTP/1.1 302 Found
Location: search.php?mod=forum&searchid=1725&orderby=lastpost&ascdesc=desc&searchsubmit=yes&kw=MT&mobile=2
                                    ↑ 从这里提取 searchid
```

### 步骤2：GET 结果页
```
GET https://bbs.binmt.cc/search.php?mod=forum&searchid={searchid}&orderby=lastpost&ascdesc=desc&searchsubmit=yes&kw={关键词}&page={页码}&mobile=2
```

### 响应2：HTML结果页
结构和帖子列表**完全相同**（`forumlist_li` 结构），可直接复用列表解析。

---

## 六、账号登录

### 请求1：GET 登录页
```
GET https://bbs.binmt.cc/member.php?mod=logging&action=login&mobile=2
```
提取：`formhash`（`value='([a-f0-9]+)'`）和 `loginhash`（`loginhash=([A-Za-z0-9]+)`）

### 请求2：POST 登录
```
POST https://bbs.binmt.cc/member.php?mod=logging&action=login&loginsubmit=yes&loginhash={loginhash}&handlekey=loginform&inajax=1

formhash={hash}&referer=https://bbs.binmt.cc/forum.php&fastloginfield=username&cookietime=31104000&username={用户名}&password={密码}&questionid=0&answer=
```

### 响应2
```xml
<!-- 成功 -->
<root><![CDATA[<p>手机号登录成功</p>]]></root>

Set-Cookie: cQWy_2132_auth=59a7PDVdlUFOrXA8...;  ← 登录凭证在这
```
提取 `Set-Cookie` 里的 `cQWy_2132_auth` 保存即可。

---

## 通用规则

| 项目 | 说明 |
|------|------|
| **登录态** | Cookie: `cQWy_2132_auth` + `cQWy_2132_saltkey` |
| **写操作凭证** | `formhash`（从任意页面HTML提取） |
| **AJAX请求** | 必须带 `X-Requested-With: XMLHttpRequest` |
| **写操作** | 必须带 `Referer` 头 |
| **返回格式** | AJAX接口 = XML `<root><![CDATA[HTML]]></root>`，取CDATA内容 |
| **编码** | 全程 UTF-8，`Content-Encoding: gzip`（HTTP库自动解压） |
| **页面URL** | `thread-{tid}-{page}-1.html` 或 `forum.php?mod=viewthread&tid={tid}` |