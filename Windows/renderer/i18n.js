'use strict';

(() => {
  const key = 'realitylink-language';
  const dictionaries = {
    en: {
      '导入链接':'Import link','设置':'Settings','连接':'Connection','日志':'Logs','未连接':'Disconnected',
      '选择一个节点开始连接':'Select a node to connect','运行日志':'Runtime logs','清空显示':'Clear',
      '导入 VLESS 链接':'Import VLESS link','导入链接':'Import link','取消':'Cancel','导入':'Import','添加节点':'Add node','购买节点':'Get nodes','支持单节点链接，以及 HTTP(S) / sub:// 订阅。':'Supports individual links and HTTP(S) / sub:// subscriptions.',
      '名称':'Name','服务器':'Server','端口':'Port','Reality 公钥':'Reality public key','uTLS 指纹':'uTLS fingerprint','协议':'Protocol','密码':'Password','安全':'Security','传输':'Transport','加密方式':'Encryption','混淆':'Obfuscation','混淆密码':'Obfuscation password','拥塞控制':'Congestion control','允许不安全证书':'Allow insecure certificates',
      '保存':'Save','自定义 sing-box 路径':'Custom sing-box path','自定义 sing-box.exe 路径':'Custom sing-box.exe path',
      '留空使用应用内置版本':'Leave empty to use the bundled version','语言':'Language',
      'TUN 首次连接使用 pkexec 请求管理员授权；同一连接内切换节点和断开无需再次授权。':'The first TUN connection requests administrator authorization through pkexec. Switching nodes and disconnecting in the same session require no additional authorization.',
      'TUN 首次连接使用 Windows UAC 请求管理员授权；同一连接内切换节点和断开无需再次授权。':'The first TUN connection requests administrator authorization through Windows UAC. Switching nodes and disconnecting in the same session require no additional authorization.',
      nodes:n=>`${n} nodes`,empty:'No nodes yet. Import a node or subscription first.',edit:'Edit',delete:'Delete',
      none:'None',fingerprint:'Fingerprint',connecting:'Connecting',connected:'Connected',switching:'Switching',
      disconnecting:'Disconnecting',failed:'Connection failed',traffic:n=>`Traffic is routed through ${n}`,
      switchingSubtitle:'Keeping the authorized session while switching nodes',connectingSubtitle:'Requesting authorization and creating the TUN interface',
      connect:'Connect',disconnect:'Disconnect',switchTo:'Switch to this node',editNode:'Edit node',
      deleteConfirm:n=>`Delete “${n}”?`,localNodes:'Local nodes',renew:'Renew subscription',deleteSubscription:'Delete subscription',deleteSubscriptionConfirm:n=>`Delete subscription “${n}” and all of its nodes?`,latencyTest:'Test latency',protocol:'Protocol',security:'Security',transport:'Transport',latency:'Latency',notTested:'Not tested',timeout:'Timeout'
    },
    zh: {
      '导入链接':'导入链接','设置':'设置','连接':'连接','日志':'日志','未连接':'未连接',
      '选择一个节点开始连接':'选择一个节点开始连接','运行日志':'运行日志','清空显示':'清空显示',
      '导入 VLESS 链接':'导入 VLESS 链接','取消':'取消','导入':'导入','添加节点':'添加节点',
      '名称':'名称','服务器':'服务器','端口':'端口','Reality 公钥':'Reality 公钥','uTLS 指纹':'uTLS 指纹','协议':'协议','密码':'密码','安全':'安全','传输':'传输','加密方式':'加密方式','混淆':'混淆','混淆密码':'混淆密码','拥塞控制':'拥塞控制','允许不安全证书':'允许不安全证书','购买节点':'购买节点','支持单节点链接，以及 HTTP(S) / sub:// 订阅。':'支持单节点链接，以及 HTTP(S) / sub:// 订阅。',
      '保存':'保存','自定义 sing-box 路径':'自定义 sing-box 路径','自定义 sing-box.exe 路径':'自定义 sing-box.exe 路径',
      '留空使用应用内置版本':'留空使用应用内置版本','语言':'语言',
      'TUN 首次连接使用 pkexec 请求管理员授权；同一连接内切换节点和断开无需再次授权。':'TUN 首次连接使用 pkexec 请求管理员授权；同一连接内切换节点和断开无需再次授权。',
      'TUN 首次连接使用 Windows UAC 请求管理员授权；同一连接内切换节点和断开无需再次授权。':'TUN 首次连接使用 Windows UAC 请求管理员授权；同一连接内切换节点和断开无需再次授权。',
      nodes:n=>`${n} 个节点`,empty:'还没有节点，请先导入节点或订阅链接',edit:'编辑',delete:'删除',
      none:'无',fingerprint:'指纹',connecting:'正在连接',connected:'已连接',switching:'正在切换',
      disconnecting:'正在断开',failed:'连接失败',traffic:n=>`流量正在通过 ${n}`,
      switchingSubtitle:'保持管理员会话，正在切换节点',connectingSubtitle:'正在请求授权并创建 TUN 接口',
      connect:'连接',disconnect:'断开连接',switchTo:'切换到此节点',editNode:'编辑节点',
      deleteConfirm:n=>`确定删除“${n}”？`,localNodes:'本地节点',renew:'更新订阅',deleteSubscription:'删除订阅',deleteSubscriptionConfirm:n=>`确定删除订阅“${n}”及其全部节点？`,latencyTest:'测试延迟',protocol:'协议',security:'安全',transport:'传输',latency:'延迟',notTested:'未测试',timeout:'超时'
    },
    ru: {
      '导入链接':'Импорт ссылки','设置':'Настройки','连接':'Подключение','日志':'Журнал','未连接':'Отключено',
      '选择一个节点开始连接':'Выберите узел для подключения','运行日志':'Журнал работы','清空显示':'Очистить',
      '导入 VLESS 链接':'Импорт ссылки VLESS','取消':'Отмена','导入':'Импорт','添加节点':'Добавить узел',
      '名称':'Название','服务器':'Сервер','端口':'Порт','Reality 公钥':'Публичный ключ Reality','uTLS 指纹':'Отпечаток uTLS','协议':'Протокол','密码':'Пароль','安全':'Защита','传输':'Транспорт','加密方式':'Шифрование','混淆':'Обфускация','混淆密码':'Пароль обфускации','拥塞控制':'Контроль перегрузки','允许不安全证书':'Разрешить небезопасные сертификаты','购买节点':'Получить узлы','支持单节点链接，以及 HTTP(S) / sub:// 订阅。':'Поддерживаются отдельные ссылки и подписки HTTP(S) / sub://.',
      '保存':'Сохранить','自定义 sing-box 路径':'Путь к sing-box','自定义 sing-box.exe 路径':'Путь к sing-box.exe',
      '留空使用应用内置版本':'Оставьте пустым для встроенной версии','语言':'Язык',
      'TUN 首次连接使用 pkexec 请求管理员授权；同一连接内切换节点和断开无需再次授权。':'Первое TUN-подключение запрашивает права через pkexec. Переключение и отключение не требуют повторной авторизации.',
      'TUN 首次连接使用 Windows UAC 请求管理员授权；同一连接内切换节点和断开无需再次授权。':'Первое TUN-подключение запрашивает права через Windows UAC. Переключение и отключение не требуют повторной авторизации.',
      nodes:n=>`Узлов: ${n}`,empty:'Узлов пока нет. Импортируйте узел или подписку.',edit:'Изменить',delete:'Удалить',
      none:'Нет',fingerprint:'Отпечаток',connecting:'Подключение',connected:'Подключено',switching:'Переключение',
      disconnecting:'Отключение',failed:'Ошибка подключения',traffic:n=>`Трафик идёт через ${n}`,
      switchingSubtitle:'Переключение узла в авторизованном сеансе',connectingSubtitle:'Запрос прав и создание интерфейса TUN',
      connect:'Подключить',disconnect:'Отключить',switchTo:'Переключиться на узел',editNode:'Изменить узел',
      deleteConfirm:n=>`Удалить «${n}»?`,localNodes:'Локальные узлы',renew:'Обновить подписку',deleteSubscription:'Удалить подписку',deleteSubscriptionConfirm:n=>`Удалить подписку «${n}» и все её узлы?`,latencyTest:'Задержка',protocol:'Протокол',security:'Защита',transport:'Транспорт',latency:'Задержка',notTested:'Не проверено',timeout:'Тайм-аут'
    }
  };
  let language = localStorage.getItem(key) || 'en';
  if (!dictionaries[language]) language = 'en';
  const originalNodes = new WeakMap();
  const listeners = [];
  const t = (name, value) => {
    const result = dictionaries[language][name];
    return typeof result === 'function' ? result(value) : (result ?? name);
  };
  function applyStatic() {
    document.documentElement.lang = language === 'zh' ? 'zh-CN' : language;
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    while (walker.nextNode()) {
      const node = walker.currentNode;
      const source = originalNodes.get(node) || node.nodeValue.trim();
      if (!originalNodes.has(node) && dictionaries.zh[source] !== undefined) originalNodes.set(node, source);
      const original = originalNodes.get(node);
      if (original) node.nodeValue = node.nodeValue.replace(node.nodeValue.trim(), t(original));
    }
    document.querySelectorAll('[placeholder]').forEach((element) => {
      const source = element.dataset.i18nPlaceholder || element.placeholder;
      if (dictionaries.zh[source] !== undefined) {
        element.dataset.i18nPlaceholder = source;
        element.placeholder = t(source);
      }
    });
    const select = document.querySelector('#languageSelect');
    if (select) select.value = language;
    document.querySelectorAll('[data-i18n-action]').forEach(element => {
      element.textContent = t(element.dataset.i18nAction);
    });
  }
  function setLanguage(next) {
    language = dictionaries[next] ? next : 'en';
    localStorage.setItem(key, language);
    applyStatic();
    listeners.forEach(listener => listener(language));
  }
  window.realityI18n = { t, current: () => language, setLanguage, onChange: listener => listeners.push(listener), applyStatic };
  applyStatic();
})();
