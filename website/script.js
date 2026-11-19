// 保留原始文字節點，切換語言時不重建連結、圖示或互動元件。
const englishTranslations = new Map(Object.entries({
  "Ripen 的三種形態：主視窗、懸浮窗與瀏海島。": "Ripen in three forms: main window, floating window, and notch island.",
  "每一段投入，": "See the time",
  "都看得見。": "you put in.",
  "工作、閱讀，或正在學的新事物。把專注分給不同分類，看看這一週，時間花在哪裡。": "Work, reading, or something you’re learning. Give each focus a project, and see where your time went this week.",
  "把累積，": "Time well spent,",
  "留成一張卡。": "made into a card.",
  "一個分類，一張成果卡。把持續投入的時間，存成自己看得見的成果。": "One project, one recap card. Turn the time you keep putting in into something you can see.",
  "選方形或直式，存成圖片、複製，或透過系統分享選單傳出去。": "Choose square or portrait. Save an image, copy it, or send it through the macOS share menu.",
  "畫面中的分類與專注紀錄為展示資料。": "Projects and focus history shown here are demonstration data.",
  "方形與直式成果卡": "Square and portrait recap cards",

  "Ripen 是原生 macOS 番茄鐘。收進瀏海、拖成懸浮窗，到點後繼續專注。免費使用，不需要帳號，專注紀錄留在你的 Mac。": "Ripen is a native macOS Pomodoro timer. Tuck it into the notch, float it above your work, and keep focusing past zero. Free to use, with no account. Your focus history stays on your Mac.",
  "Ripen — 留一點空間，給專注。": "Ripen — A little space for focus.",
  "跳至主要內容": "Skip to main content",
  "Ripen 首頁": "Ripen home",
  "主要導覽": "Main navigation",
  "看看 Ripen": "Explore Ripen",
  "常見問題": "FAQ",
  "（另開分頁）": " (opens in a new tab)",
  "給 Mac 的專注小工具": "A little focus companion for Mac",
  "留一點空間，": "A little space",
  "給專注。": "for focus.",
  "免費下載 macOS 版": "Download free for macOS",
  "產品特色摘要": "Features at a glance",
  "原生 macOS": "Native macOS",
  "免費使用": "Free to use",
  "紀錄留在本機": "History stays local",
  "自由選擇支持": "Optional support",
  "找到你的": "Find your space",
  "專注位置。": "to focus.",
  "需要時就在眼前，忙起來就退到一旁。": "There when you need it. Out of the way when you don’t.",
  "同一個計時，三種相處方式。": "One timer. Three ways to keep it close.",
  "主視窗": "Main window",
  "懸浮窗": "Floating window",
  "瀏海島": "Notch island",
  "完整控制，安靜地陪你開始。": "All the controls. A quiet place to begin.",
  "永遠置頂，三種尺寸，記得你放的位置。": "Always on top. Three sizes. Right where you left it.",
  "移入展開控制，往下拉回主視窗。沒有瀏海也能用。": "Hover for controls. Pull down for the main window. Works without a notch, too.",
  "給還沒寫完的那一句。": "For the thought you haven’t finished yet.",
  "到點了，": "Time’s up.",
  "也不必急著結束。": "Take your time.",
  "提示音響起後，Ripen 會換個顏色，繼續往上計時。把這個想法寫完，準備好了，再按「完成」。": "After the chime, Ripen changes color and keeps counting up. Finish your thought, then press Done when you’re ready.",
  "專注紀錄會算進超時的長度；鎖定或睡眠期間的超時不會持續累加。": "Your focus history includes overtime. Time spent with your Mac locked or asleep doesn’t add to it.",
  "倒數到零後進入超時": "The countdown reaches zero and continues into overtime",
  "把簡單的事，": "The little things,",
  "照顧好。": "taken care of.",
  "你的紀錄，只留給你": "Your history is yours",
  "不用註冊、不需要帳號。專注紀錄保存在你的 Mac，不用把一天交給另一個雲端服務。": "No sign-up. No account. Your focus history stays on your Mac, without handing your day to another cloud service.",
  "照自己的節奏": "Follow your own rhythm",
  "調整專注、短休息與長休息的時間。用全域快速鍵開始或暫停，手不用離開鍵盤。": "Choose your focus, short break, and long break lengths. Start or pause with a global shortcut, without leaving the keyboard.",
  "切換最近 7 天或 30 天，看專注了多久、時間花在哪些分類。點進分類，看它累積了多少。": "Switch between the last 7 and 30 days to see how long you focused and which projects took the time. Open a project to see its total.",
  "下一段專注，": "Your next focus",
  "留給 Ripen。": "starts with Ripen.",
  "免費使用，不需要帳號。": "Free to use. No account needed.",
  "安裝後可從 App 選單手動檢查更新。": "Once installed, check for updates from the app menu.",
  "下載 Ripen 0.3.5": "Download Ripen 0.3.5",
  "適用系統": "Requires",
  "macOS 14 Sonoma 以上": "macOS 14 Sonoma or later",
  "支援晶片": "Processors",
  "Apple silicon 與 Intel": "Apple silicon and Intel",
  "介面語言": "Languages",
  "繁體中文、English": "Traditional Chinese and English",
  "查看所有版本與更新說明": "View all releases and release notes",
  "你可能想知道。": "A few things to know.",
  "真的可以免費使用嗎？": "Is it really free?",
  "可以。目前 Mac 版免費使用，沒有試用倒數，也不用先付款。Ko-fi 是自願支持，不會影響你使用 App。": "Yes. The current Mac version is free, with no trial countdown or upfront payment. Ko-fi support is optional and doesn’t affect your access to the app.",
  "沒有瀏海的 Mac 也能用嗎？": "Does it work on a Mac without a notch?",
  "可以。瀏海島會顯示在螢幕頂端中央；你也可以使用主視窗或置頂懸浮窗。": "Yes. The notch island sits at the top center of your screen. You can also use the main window or the always-on-top floating window.",
  "專注紀錄會上傳嗎？": "Is my focus history uploaded?",
  "不會，紀錄保存在你的 Mac。目前沒有跨裝置同步。App 只有在你按「檢查更新」時才會連網查詢與下載版本。": "No. Your history stays on your Mac, with no cross-device sync at present. The app only goes online to look for and download releases when you click Check for Updates.",
  "有 iPhone 或 Apple Watch 版嗎？": "Is there an iPhone or Apple Watch version?",
  "目前只有 Mac 版，手機與手錶版尚未提供。": "Ripen is currently available for Mac only. iPhone and Apple Watch versions are not available yet.",
  "如何支持開發？": "How can I support development?",
  "如果 Ripen 讓你的工作日順了一點，可以透過": "If Ripen makes your workday a little smoother, you can ",
  "Ko-fi 自願支持": "support it on Ko-fi",
  "。不支持也能完整使用目前的免費版本。": ". You can use all the features of the current free version without contributing.",
  "在 Ko-fi 支持開發": "Support on Ko-fi",
  "回到 Ripen 首頁": "Back to Ripen home",
  "留一點空間，給專注。": "A little space for focus.",
  "獨立開發，為日常而做。": "Independently made for everyday life.",
  "時間留在視線裡，注意力留給手上的事。": "Keep time in sight and your attention on your work.",
  "免費・開源・不需帳號": "Free · Open source · No account needed",
  "macOS 14 以上・未經 Apple 公證，第一次打開要手動允許一次。": "macOS 14 or later · Not notarized by Apple. Allow it once on first launch.",
  "喜歡 Ripen？": "Enjoying Ripen? ",
  "歡迎在 GitHub 給個 star，支持後續開發。": "Star it on GitHub to support future development.",
  "展開的瀏海島：顯示 18:42、進度條與控制按鈕": "Expanded notch island showing 18:42, a progress bar, and controls",
  "Ripen 主視窗：圓環倒數 18:42，分類為深度工作，可暫停": "Ripen’s main window with a countdown ring at 18:42, the Deep Work project, and a pause button",
  "懸浮窗：顯示 18:42、進度條與控制按鈕": "Floating window showing 18:42, a progress bar, and controls",
  "下載": "Download",
  "玻璃外觀的主視窗：圓環倒數 18:42 與暫停按鈕": "Main window in the glass appearance with a countdown ring at 18:42 and a pause button",
  "玻璃外觀的懸浮窗：顯示時間、進度與操作按鈕": "Floating window in the glass appearance with time, progress, and controls",
  "滑鼠移入後展開的瀏海島與計時控制": "Notch island expanded on hover to show timer controls",
  "專注超時：圓環與時間以洋紅色顯示 +03:17，下方是完成按鈕": "Focus overtime with the ring and time in magenta at +03:17, above a Done button",
  "統計頁：最近 7 天的專注依分類代表色堆疊，下方列出各分類的累積時間；展示資料": "Statistics page: seven days of focuses stacked by project color, with time per project below; demonstration data",
  "方形成果卡：分類累積時間、今日投入、完成次數、專注天數與最近 7 天；展示資料": "Square recap card with total focus, today, focus count, focus days, and the last 7 days; demonstration data",
  "直式成果卡，內容與方形相同；展示資料": "Portrait recap card with the same content as the square one; demonstration data",
  "切換最近 7 天或 30 天，看專注了多久、時間花在哪些分類。點進分類，看它累積了多少。": "Switch between the last 7 and 30 days to see how long you focused and which projects took the time. Open a project to see its total.",
  "按錯了，也能復原": "Undo a slip",
  "跳過、重設與完成之後 5 秒內，按倒數膠囊或 ⌘Z 就能復原。": "For 5 seconds after you skip, reset, or finish, press the countdown capsule or ⌘Z to undo it.",
  "換一台 Mac，也帶得走": "Bring it to a new Mac",
  "備份專注紀錄與分類，到新 Mac 還原；也能把完成的專注匯出成 CSV。": "Back up your focus history and projects, then restore them on a new Mac. You can also export completed focuses as CSV.",
  "下載後打開 DMG，將 Ripen 拖進「應用程式」。": "Open the DMG and drag Ripen into Applications.",
  "或用 Homebrew 安裝": "Or install with Homebrew",
  "複製安裝指令": "Copy the install command",
  "複製": "Copy",
  "已複製": "Copied",
  "無法自動複製，請手動選取指令。": "Couldn’t copy automatically. Select the command by hand.",
  "第一次打開，要手動允許一次": "Allow it once on first launch",
  "Ripen 未經 Apple 公證，第一次打開會被 Gatekeeper 擋下。允許一次之後，就能正常雙擊打開。": "Ripen isn’t notarized by Apple, so Gatekeeper blocks the first launch. After you allow it once, it opens normally.",
  "macOS 15 以上": "macOS 15 or later",
  "在「應用程式」資料夾對 Ripen 按右鍵（或 Control 點按）選「打開」，再於對話框按「打開」。": "In Applications, right-click (or Control-click) Ripen, choose Open, then click Open in the dialog.",
  "先雙擊 Ripen 讓系統擋下，再到「系統設定 › 隱私權與安全性」，在下方找到 Ripen 按「強制打開」並確認。": "Double-click Ripen and let macOS block it. Then go to System Settings › Privacy & Security, find Ripen near the bottom, click Open Anyway, and confirm.",
  "播放": "Play",
  "暫停": "Pause",
  "語言": "Language"
}));
const localizedText = [];
const textWalker = document.createTreeWalker(document.documentElement, NodeFilter.SHOW_TEXT);
while (textWalker.nextNode()) {
  const node = textWalker.currentNode;
  if (node.parentElement.closest('script, style, option')) continue;
  const original = node.nodeValue;
  const translation = englishTranslations.get(original.trim());
  if (translation !== undefined) localizedText.push({ node, original, translation });
}

const localizedAttributes = [];
for (const element of document.querySelectorAll('[aria-label], [alt], meta[name="description"]')) {
  for (const attribute of ['aria-label', 'alt', 'content']) {
    const original = element.getAttribute(attribute);
    const translation = englishTranslations.get(original);
    if (translation !== undefined) localizedAttributes.push({ element, attribute, original, translation });
  }
}

const localizedImages = Array.from(document.querySelectorAll('img[data-src-en]'), (element) => ({
  element,
  original: element.getAttribute('src'),
  translation: element.dataset.srcEn,
}));

const languageSelect = document.getElementById('language-select');
const languageStorageKey = 'ripen-language';
const languageListeners = [];
const localized = (text) => (document.documentElement.lang === 'en' ? englishTranslations.get(text) : text);
function setLanguage(language) {
  document.documentElement.lang = language;
  languageSelect.value = language;
  for (const { node, original, translation } of localizedText) {
    node.nodeValue = language === 'en' ? original.replace(original.trim(), () => translation) : original;
  }
  for (const { element, attribute, original, translation } of localizedAttributes) {
    element.setAttribute(attribute, language === 'en' ? translation : original);
  }
  for (const { element, original, translation } of localizedImages) {
    element.setAttribute('src', language === 'en' ? translation : original);
  }
  for (const listener of languageListeners) listener();
}

let savedLanguage;
try {
  savedLanguage = localStorage.getItem(languageStorageKey);
} catch (error) {
  // 瀏覽器禁止儲存時，仍可切換語言，預設使用繁體中文。
  console.warn('無法讀取語言偏好：', error);
}
setLanguage(savedLanguage === 'en' ? 'en' : 'zh-Hant');
languageSelect.closest('label').hidden = false;
languageSelect.addEventListener('change', () => {
  setLanguage(languageSelect.value);
  try {
    localStorage.setItem(languageStorageKey, languageSelect.value);
  } catch (error) {
    console.warn('無法儲存語言偏好：', error);
  }
});

const copyButton = document.querySelector('.copy-button');
const copyStatus = document.querySelector('.copy-status');
let copyStatusTimer;
copyButton.addEventListener('click', async () => {
  const command = document.querySelector('.command code').textContent;
  try {
    await navigator.clipboard.writeText(command);
    copyStatus.textContent = localized('已複製');
  } catch (error) {
    console.warn('無法寫入剪貼簿：', error);
    copyStatus.textContent = localized('無法自動複製，請手動選取指令。');
  }
  clearTimeout(copyStatusTimer);
  copyStatusTimer = setTimeout(() => { copyStatus.textContent = ''; }, 2500);
});

// 靜態畫面留在底層，影片可播放時才淡入；載入失敗就繼續顯示靜態畫面。
// 預設在畫面內自動靜音循環；開啟減少動態效果時，由使用者按下才播放。
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
function setUpClip(clip) {
  const video = document.createElement('video');
  video.muted = true;
  video.loop = true;
  video.playsInline = true;
  video.preload = 'none';
  // 影片無旁白，內容與底層靜態畫面的 alt 相同，不重複朗讀。
  video.setAttribute('aria-hidden', 'true');
  clip.append(video);

  const toggle = document.createElement('button');
  toggle.className = 'clip-toggle';
  toggle.type = 'button';
  clip.append(toggle);

  let inView = false;
  let pausedByUser = reducedMotion.matches;
  const updateLabel = () => { toggle.textContent = localized(video.paused ? '播放' : '暫停'); };
  const sync = () => {
    if (inView && !pausedByUser) {
      video.play().catch((error) => { if (error.name !== 'AbortError') console.warn('影片無法播放：', error); });
    } else {
      video.pause();
    }
  };
  const loadSource = () => {
    video.src = document.documentElement.lang === 'en' ? clip.dataset.videoEn : clip.dataset.video;
    clip.classList.remove('is-ready');
    updateLabel();
    sync();
  };

  video.addEventListener('playing', () => clip.classList.add('is-ready'));
  video.addEventListener('play', updateLabel);
  video.addEventListener('pause', updateLabel);
  video.addEventListener('error', () => {
    console.warn('影片載入失敗，改顯示靜態畫面：', video.src);
    video.remove();
    toggle.remove();
  });
  toggle.addEventListener('click', () => {
    pausedByUser = !video.paused;
    sync();
  });
  new IntersectionObserver((entries) => {
    inView = entries.at(-1).isIntersecting;
    sync();
  }, { threshold: 0.4 }).observe(clip);
  languageListeners.push(loadSource);
  loadSource();
}
document.querySelectorAll('.clip[data-video][data-video-en]').forEach(setUpClip);
