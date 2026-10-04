part of '../forum_parser.dart';

extension ForumParserEditorParserPart on ForumParser {
  PostEditorForm parsePostEditorForm(
    String body, {
    required String fallbackFid,
    String fallbackTid = '',
    String fallbackPid = '',
    int fallbackPage = 1,
  }) {
    final document = html_parser.parse(body);
    final form = document.querySelector('form#postform') ??
        document.querySelector('form[action*="mod=post"]');

    String valueOf(String name) {
      final inForm = form
          ?.querySelector('input[name="$name"]')
          ?.attributes['value']
          ?.trim();
      if (inForm != null && inForm.isNotEmpty) return inForm;

      // 移动模板偶尔会改 form 包裹层，但真实字段仍在页面里。
      return document
              .querySelector('input[name="$name"]')
              ?.attributes['value']
              ?.trim() ??
          '';
    }

    final formhash = valueOf('formhash');
    final posttime = valueOf('posttime');
    final fid = valueOf('fid').isNotEmpty ? valueOf('fid') : fallbackFid;
    final tid = valueOf('tid').isNotEmpty ? valueOf('tid') : fallbackTid;
    final pid = valueOf('pid').isNotEmpty ? valueOf('pid') : fallbackPid;
    final parsedPage = int.tryParse(valueOf('page')) ?? fallbackPage;
    final subject = form?.querySelector('input[name="subject"]')?.attributes['value'] ??
        document.querySelector('input[name="subject"]')?.attributes['value'] ??
        '';
    final message = form?.querySelector('textarea[name="message"]')?.text ??
        document.querySelector('textarea[name="message"]')?.text ??
        '';

    // Discuz 移动端上传组件把 uid/hash 放在 JS 的 uploadformdata 中，
    // 不是普通 input。附件上传必须使用这组页面级凭证，不能拿 formhash 代替。
    final uploadBlock = RegExp(
      r'''uploadformdata\s*:\s*\{([^}]*)\}''',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(body)?.group(1) ?? '';
    final uploadUid = RegExp(
      r'''["']?uid["']?\s*:\s*["']?(\d+)["']?''',
      caseSensitive: false,
    ).firstMatch(uploadBlock)?.group(1) ?? '';
    final uploadHash = RegExp(
      r'''["']?hash["']?\s*:\s*["']([a-fA-F0-9]+)["']''',
      caseSensitive: false,
    ).firstMatch(uploadBlock)?.group(1) ?? '';
    final maxUploadSizeKb = int.tryParse(
          RegExp(
            r'''maxfilesize\s*[:=]\s*["']?(\d+)["']?''',
            caseSensitive: false,
          ).firstMatch(body)?.group(1) ?? '',
        ) ??
        1024;
    final typeSelect = form?.querySelector('select[name="typeid"]') ??
        document.querySelector('select[name="typeid"]');
    final threadTypes = <ThreadTypeOption>[];
    var selectedTypeId = '';
    if (typeSelect != null) {
      for (final option in typeSelect.querySelectorAll('option')) {
        final id = (option.attributes['value'] ?? '').trim();
        final name = _cleanInline(option.text);
        if (option.attributes.containsKey('selected')) {
          selectedTypeId = id;
        }
        if (id.isEmpty || id == '0' || name.isEmpty || name == '请选择') {
          continue;
        }
        threadTypes.add(ThreadTypeOption(id: id, name: name));
      }
    }
    if ((selectedTypeId.isEmpty || selectedTypeId == '0') &&
        fid == '40' &&
        threadTypes.any((item) => item.id == '59')) {
      selectedTypeId = '59';
    }

    final attachmentAids = <String>{};
    for (final input in document.querySelectorAll('input[name]')) {
      final name = input.attributes['name'] ?? '';
      final match = RegExp(
        r'^attachnew\[(\d+)\]\[(?:description|readperm|price)\]$',
        caseSensitive: false,
      ).firstMatch(name);
      final aid = match?.group(1);
      if (aid != null && aid.isNotEmpty) attachmentAids.add(aid);
    }

    return PostEditorForm(
      formhash: formhash,
      posttime: posttime,
      fid: fid,
      tid: tid,
      pid: pid,
      page: parsedPage,
      subject: subject,
      message: message,
      deleteValue: valueOf('delete').isEmpty ? '0' : valueOf('delete'),
      allowNoticeAuthor:
          valueOf('allownoticeauthor').isEmpty ? '1' : valueOf('allownoticeauthor'),
      useSig: valueOf('usesig').isEmpty ? '1' : valueOf('usesig'),
      uploadUid: uploadUid,
      uploadHash: uploadHash,
      maxUploadSizeKb: maxUploadSizeKb,
      attachmentAids: attachmentAids.toList(growable: false),
      threadTypes: List<ThreadTypeOption>.unmodifiable(threadTypes),
      selectedTypeId: selectedTypeId,
    );
  }

  PostAttachmentUploadResult parsePostAttachmentUploadResponse(String body) {
    final raw = unwrapAjax(body).trim();
    final markerIndex = raw.indexOf('DISCUZUPLOAD|');
    if (markerIndex < 0) {
      final text = html_parser.parseFragment(raw).text?.trim() ?? '';
      return PostAttachmentUploadResult(
        success: false,
        message: text.isEmpty ? '附件上传失败' : text,
      );
    }

    final payload = raw.substring(markerIndex).split(RegExp(r'[\r\n<]')).first;
    final parts = payload.split('|');
    if (parts.length < 4 || parts.first != 'DISCUZUPLOAD') {
      return const PostAttachmentUploadResult(
        success: false,
        message: '附件上传响应格式异常',
      );
    }

    final status = parts.length > 2 ? parts[2].trim() : '';
    final aid = parts.length > 3 ? parts[3].trim() : '';
    final relativePath = parts.length > 5 ? parts[5].trim() : '';
    final fileName = parts.length > 6 ? parts[6].trim() : '';
    final limitInfo = parts.length > 7 ? parts[7].trim() : '';

    if (status != '0' || aid.isEmpty) {
      final statusReason = switch (status) {
        '1' => '服务器写入失败',
        '2' => '图片超过论坛大小限制',
        '3' => '论坛不支持该图片格式',
        '9' => '图片无效或尺寸过小',
        _ => '服务器拒绝了附件',
      };
      final reason = limitInfo.isNotEmpty && limitInfo != '0'
          ? limitInfo
          : statusReason;
      return PostAttachmentUploadResult(
        success: false,
        message: '上传失败：$reason',
        limitInfo: limitInfo,
      );
    }

    final url = relativePath.isEmpty
        ? ''
        : 'https://cdn.binmt.cc/data/attachment/forum/$relativePath';
    return PostAttachmentUploadResult(
      success: true,
      message: '上传成功',
      aid: aid,
      relativePath: relativePath,
      fileName: fileName,
      url: url,
      limitInfo: limitInfo,
    );
  }

  String? _extractFormhash(String body) {
    final js = RegExp(
      r'''formhash\s*=\s*['"]([a-fA-F0-9]+)['"]''',
      caseSensitive: false,
    ).firstMatch(body);
    if (js != null) return js.group(1);

    final input = RegExp(
      r'''name\s*=\s*['"]formhash['"][^>]*value\s*=\s*['"]([a-fA-F0-9]+)['"]''',
      caseSensitive: false,
    ).firstMatch(body);
    if (input != null) return input.group(1);

    final valueFirst = RegExp(
      r'''value\s*=\s*['"]([a-fA-F0-9]+)['"][^>]*name\s*=\s*['"]formhash['"]''',
      caseSensitive: false,
    ).firstMatch(body);
    return valueFirst?.group(1);
  }
}
