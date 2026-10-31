// 保留原始文字節點，切換語言時不重建連結、圖示或互動元件。
const englishTranslations = new Map(Object.entries({
  "每一段投入，": "See the time",
  "都看得見。": "you put in.",
  "工作、閱讀，或正在學的新事物。把專注分給不同分類，看看這一週，時間花在哪裡。": "Work, reading, or something you’re learning. Give each focus a project, and see where your time went this week.",
  "今天的投入、七天的節奏、一路累積的時間，都留在你的 Mac。": "Today’s effort, your weekly rhythm, and all the time you’ve put in. Kept on your Mac.",
  "把累積，": "Time well spent,",
  "留成一張卡。": "made into a card.",
  "一個分類，一張成果卡。把持續投入的時間，存成自己看得見的成果。": "One project, one recap card. Turn the time you keep putting in into something you can see.",
  "選方形或直式，存成圖片、複製，或透過系統分享選單傳出去。": "Choose square or portrait. Save an image, copy it, or send it through the macOS share menu.",
  "畫面中的分類與專注紀錄為展示資料。": "Projects and focus history shown here are demonstration data.",
  "分類統計：依代表色呈現最近七天的專注；展示資料": "Project statistics: seven days of focuses stacked by project color; demonstration data",
  "方形與直式成果卡": "Square and portrait recap cards",
  "方形分類成果卡；展示資料": "Square project recap card; demonstration data",
  "直式分類成果卡；展示資料": "Portrait project recap card; demonstration data",

  "Ripen 是原生 macOS 番茄鐘。收進瀏海、拖成懸浮窗，到點後繼續專注。免費使用，不需要帳號，專注紀錄留在你的 Mac。": "Ripen is a native macOS Pomodoro timer. Tuck it into the notch, float it above your work, and keep focusing past zero. Free to use, with no account. Your focus history stays on your Mac.",
  "Ripen — 留一點空間，給專注。": "Ripen — A little space for focus.",
  "跳至主要內容": "Skip to main content",
  "Ripen 首頁": "Ripen home",
  "主要導覽": "Main navigation",
  "看看 Ripen": "Explore Ripen",
  "常見問題": "FAQ",
  "支持開發": "Support",
  "（另開分頁）": " (opens in a new tab)",
  "給 Mac 的專注小工具": "A little focus companion for Mac",
  "留一點空間，": "A little space",
  "給專注。": "for focus.",
  "時間留在視線裡，": "Keep time in sight.",
  "注意力留給手上的事。": "Keep your attention on your work.",
  "免費下載 macOS 版": "Download free for macOS",
  "macOS 14 以上・不需要帳號": "macOS 14 or later · No account needed",
  "免費使用，自願支持開發": "Free to use. Support is optional.",
  "Ripen 暖瓷白主視窗實際截圖": "Screenshot of Ripen’s warm white main window",
  "Ripen 暖瓷白主視窗：圓環顯示剩餘專注時間，可暫停與切換階段": "Ripen’s warm white main window with a focus countdown ring, pause button, and session controls",
  "產品特色摘要": "Features at a glance",
  "原生 macOS": "Native macOS",
  "免費使用": "Free to use",
  "紀錄留在本機": "History stays local",
  "自由選擇支持": "Optional support",
  "找到你的": "Find your space",
  "專注位置。": "to focus.",
  "需要時就在眼前，忙起來就退到一旁。": "There when you need it. Out of the way when you don’t.",
  "同一個計時，三種相處方式。": "One timer. Three ways to keep it close.",
  "切換計時形態": "Choose a timer view",
  "主視窗": "Main window",
  "坐下來，開始這一段。": "Settle in and start a session.",
  "懸浮窗": "Floating window",
  "拖出圓環，放在順眼的地方。": "Drag the ring out and put it where it feels right.",
  "瀏海島": "Notch island",
  "收進螢幕頂端，抬眼就看見。": "Tuck it at the top of your screen, a glance away.",
  "Main window：主視窗圓環計時與暫停按鈕": "Main window with a countdown ring and pause button",
  "完整控制，安靜地陪你開始。": "All the controls. A quiet place to begin.",
  "Floating window：置頂懸浮窗顯示時間、進度與操作按鈕": "Always-on-top floating window with time, progress, and controls",
  "永遠置頂，三種尺寸，記得你放的位置。": "Always on top. Three sizes. Right where you left it.",
  "Notch island：滑鼠移入後展開的瀏海島與計時控制": "Notch island expanded on hover to show timer controls",
  "移入展開控制，往下拉回主視窗。沒有瀏海也能用。": "Hover for controls. Pull down for the main window. Works without a notch, too.",
  "App 實際截圖": "Actual app screenshots",
  "Overtime：專注到點後，以青綠色 +03:17 繼續計時": "Focus overtime counting up in teal at +03:17",
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
  "看見這一週的累積": "See your week add up",
  "今天專注幾次、花了多久，最近七天依分類疊成長條。點進分類，看它累積了多少。": "See today’s focus sessions and minutes, with the past seven days stacked by project. Open a project to see its total.",
  "把累積做成一張卡": "Turn it into a card",
  "每個分類都有一張成果卡，方形或直式版面。存成圖片、複製，或用系統分享選單傳出去。": "Every project has a recap card in a square or portrait layout. Save it as an image, copy it, or share it from the macOS share menu.",
  "下一段專注，": "Your next focus",
  "留給 Ripen。": "starts with Ripen.",
  "免費使用，不需要帳號。": "Free to use. No account needed.",
  "如果它剛好幫上忙，再請我喝杯咖啡。": "If it helps your day, you can buy me a coffee.",
  "Mac 版現已開放下載": "Available now for Mac",
  "下載後打開 DMG，將 Ripen 拖進「應用程式」。": "Open the DMG and drag Ripen into Applications.",
  "安裝後可從 App 選單手動檢查更新。": "Once installed, check for updates from the app menu.",
  "下載 Ripen 0.2.0": "Download Ripen 0.2.0",
  "適用系統": "Requires",
  "macOS 14 Sonoma 以上": "macOS 14 Sonoma or later",
  "支援晶片": "Processors",
  "Apple silicon 與 Intel": "Apple silicon and Intel",
  "介面語言": "Languages",
  "繁體中文、English": "Traditional Chinese and English",
  "目前版本尚未經 Apple 公證。首次開啟可能需要到「系統設定 › 隱私權與安全性」允許開啟。": "This version is not notarized by Apple. On first launch, you may need to allow it in System Settings › Privacy & Security.",
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
  "一個小工具，": "A little app,",
  "慢慢做好。": "made with care.",
  "喜歡 Ripen 的話，一杯咖啡就是很好的鼓勵。": "Enjoying Ripen? A coffee is a lovely way to encourage its development.",
  "在 Ko-fi 支持開發": "Support on Ko-fi",
  "回到 Ripen 首頁": "Back to Ripen home",
  "留一點空間，給專注。": "A little space for focus.",
  "獨立開發，為日常而做。": "Independently made for everyday life.",
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

const tabs = Array.from(document.querySelectorAll('[role="tab"]'));
const mobileLayout = window.matchMedia('(max-width: 680px)');

function updateTabOrientation() {
  document.querySelector('[role="tablist"]').setAttribute('aria-orientation', mobileLayout.matches ? 'horizontal' : 'vertical');
}

updateTabOrientation();
mobileLayout.addEventListener('change', updateTabOrientation);

function selectTab(selectedTab) {
  for (const tab of tabs) {
    const selected = tab === selectedTab;
    tab.setAttribute('aria-selected', String(selected));
    tab.tabIndex = selected ? 0 : -1;
    document.getElementById(tab.getAttribute('aria-controls')).hidden = !selected;
  }
}

for (const tab of tabs) {
  tab.addEventListener('click', () => selectTab(tab));
  tab.addEventListener('keydown', (event) => {
    const index = tabs.indexOf(tab);
    let nextIndex;
    if (event.key === 'ArrowDown' || event.key === 'ArrowRight') nextIndex = (index + 1) % tabs.length;
    if (event.key === 'ArrowUp' || event.key === 'ArrowLeft') nextIndex = (index - 1 + tabs.length) % tabs.length;
    if (event.key === 'Home') nextIndex = 0;
    if (event.key === 'End') nextIndex = tabs.length - 1;
    if (nextIndex === undefined) return;
    event.preventDefault();
    selectTab(tabs[nextIndex]);
    tabs[nextIndex].focus();
  });
}
