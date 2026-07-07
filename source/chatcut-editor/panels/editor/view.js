// ChatCutPro Editor workspace
// main.workspace: the single video editing desk.
(() => {
  if (!window.Clacky || !Clacky.ext) return;
  if (window.__chatcutEditorLoaded === "workspace-v5") return;
  window.__chatcutEditorLoaded = "workspace-v5";

  const S = window.__chatcutEditorState || (window.__chatcutEditorState = {});
  Object.assign(S, {
    view: S.view || "loading",
    env: S.env || null,
    envChecked: !!S.envChecked,
    projectId: S.projectId || null,
    videoFile: S.videoFile || "",
    videoSrc: S.videoSrc || "",
    localVideoUrl: S.localVideoUrl || "",
    transcript: S.transcript || null,
    captions: S.captions || [],
    scenes: S.scenes || [],
    highlights: S.highlights || [],
    timeline: S.timeline || null,
    currentVersion: S.currentVersion || 0,
    versions: S.versions || [],
    versionDiff: S.versionDiff || null,
    media: S.media || null,
    motionGraphics: S.motionGraphics || [],
    editDecisions: S.editDecisions || [],
    projectAutoLoaded: !!S.projectAutoLoaded,
    projectLoading: !!S.projectLoading,
    suggestions: S.suggestions || [],
    lastResult: S.lastResult || "",
    status: S.status || "环境检测中",
    busy: !!S.busy,
    uploading: !!S.uploading,
  });
  S.renderers = new Set();

  let style = document.getElementById("chatcut-editor-style");
  if (!style) {
    style = document.createElement("style");
    style.id = "chatcut-editor-style";
    document.head.appendChild(style);
  }
  style.textContent = `
      .cc-composer, .cc-panel { display:none !important; }
      .ccw-fallback-hidden { display:none !important; }

      .ccw-root {
        box-sizing:border-box;
        width:100%;
        height:min(900px, calc(100vh - 128px));
        min-height:620px;
        padding:14px 18px 16px;
        color:var(--color-text-primary);
        background:var(--color-bg-primary);
        font:13px/1.45 var(--font-sans,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif);
        display:grid;
        grid-template-rows:auto minmax(300px, 1.35fr) minmax(220px, .9fr);
        gap:12px;
        overflow:hidden;
      }
      .ccw-slot-banner {
        max-width:1280px;
        height:min(840px, calc(100vh - 190px));
        min-height:560px;
        margin:0 auto 10px;
        border-bottom:1px solid var(--color-border-secondary);
      }
      .ccw-topbar {
        min-width:0;
        display:flex;
        align-items:center;
        gap:12px;
        padding-bottom:10px;
        border-bottom:1px solid var(--color-border-secondary);
      }
      .ccw-title {
        flex:none;
        min-width:150px;
        display:flex;
        flex-direction:column;
        gap:2px;
      }
      .ccw-title strong {
        font-size:14px;
        line-height:18px;
        font-weight:780;
      }
      .ccw-title span,
      .ccw-muted {
        color:var(--color-text-tertiary);
      }
      .ccw-title span {
        font-size:11px;
        white-space:nowrap;
        overflow:hidden;
        text-overflow:ellipsis;
        max-width:240px;
      }
      .ccw-toolbar {
        flex:1;
        min-width:0;
        display:flex;
        align-items:center;
        gap:6px;
        overflow:auto;
        scrollbar-width:none;
      }
      .ccw-toolbar::-webkit-scrollbar { display:none; }
      .ccw-tool {
        flex:none;
        height:30px;
        border:1px solid var(--color-border-secondary);
        border-radius:6px;
        background:var(--color-bg-primary);
        color:var(--color-text-secondary);
        padding:0 10px;
        font:12px var(--font-sans,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif);
        cursor:pointer;
      }
      .ccw-tool:hover {
        border-color:var(--color-accent-primary);
        color:var(--color-accent-primary);
        background:var(--color-bg-hover);
      }
      .ccw-tool.primary {
        border-color:var(--color-accent-primary);
        background:var(--color-accent-primary);
        color:#fff;
      }
      .ccw-tool:disabled {
        opacity:.48;
        cursor:not-allowed;
      }
      .ccw-status {
        flex:none;
        max-width:220px;
        color:var(--color-text-tertiary);
        font-size:12px;
        white-space:nowrap;
        overflow:hidden;
        text-overflow:ellipsis;
      }
      .ccw-upper {
        min-height:0;
        display:grid;
        grid-template-columns:minmax(420px, 1.55fr) minmax(260px, .65fr);
        gap:12px;
        overflow:hidden;
      }
      .ccw-preview {
        min-width:0;
        min-height:0;
        background:#08090b;
        border:1px solid #1b1f27;
        border-radius:8px;
        display:flex;
        align-items:center;
        justify-content:center;
        position:relative;
        overflow:hidden;
      }
      .ccw-preview video {
        width:100%;
        height:100%;
        object-fit:contain;
        background:#050506;
      }
      .ccw-drop {
        width:min(520px, 88%);
        min-height:210px;
        border:1.5px dashed rgba(255,255,255,.26);
        border-radius:8px;
        color:rgba(255,255,255,.82);
        display:flex;
        flex-direction:column;
        align-items:center;
        justify-content:center;
        gap:9px;
        text-align:center;
        padding:22px;
        cursor:pointer;
        background:rgba(255,255,255,.035);
      }
      .ccw-drop.drag,
      .ccw-drop:hover {
        border-color:var(--color-accent-primary);
        color:#fff;
      }
      .ccw-frame-mark {
        width:72px;
        height:50px;
        border:1px solid rgba(255,255,255,.55);
        border-radius:7px;
        display:flex;
        align-items:center;
        justify-content:center;
        font-weight:760;
        font-size:12px;
        color:rgba(255,255,255,.78);
      }
      .ccw-caption-overlay {
        position:absolute;
        left:20px;
        right:20px;
        bottom:18px;
        min-height:34px;
        display:flex;
        align-items:center;
        justify-content:center;
        pointer-events:none;
      }
      .ccw-caption-text {
        max-width:92%;
        padding:7px 12px;
        border-radius:6px;
        background:rgba(0,0,0,.7);
        color:#fff;
        font-size:16px;
        line-height:1.3;
        font-weight:760;
        text-align:center;
        text-shadow:0 1px 2px rgba(0,0,0,.75);
      }
      .ccw-side {
        min-width:0;
        min-height:0;
        border:1px solid var(--color-border-secondary);
        border-radius:8px;
        background:var(--color-bg-secondary);
        display:grid;
        grid-template-rows:auto auto minmax(0, 1fr);
        overflow:hidden;
      }
      .ccw-panel-head {
        display:flex;
        align-items:center;
        gap:8px;
        padding:10px 12px;
        border-bottom:1px solid var(--color-border-secondary);
      }
      .ccw-panel-spacer { flex:1; }
      .ccw-panel-title {
        font-size:12px;
        font-weight:760;
        color:var(--color-text-secondary);
      }
      .ccw-panel-body {
        min-height:0;
        overflow:auto;
        padding:10px 12px;
      }
      .ccw-beginner {
        display:grid;
        gap:8px;
        margin-bottom:10px;
      }
      .ccw-beginner-actions {
        display:grid;
        grid-template-columns:repeat(3, minmax(0, 1fr));
        gap:6px;
      }
      .ccw-action {
        min-width:0;
        height:38px;
        border:1px solid var(--color-border-secondary);
        border-radius:6px;
        background:var(--color-bg-primary);
        color:var(--color-text-secondary);
        font-size:12px;
        font-weight:760;
        cursor:pointer;
      }
      .ccw-action.primary {
        background:var(--color-accent-primary);
        border-color:var(--color-accent-primary);
        color:#fff;
      }
      .ccw-action:disabled {
        opacity:.48;
        cursor:not-allowed;
      }
      .ccw-stats {
        display:grid;
        grid-template-columns:1fr;
        border-bottom:1px solid var(--color-border-secondary);
      }
      .ccw-stat {
        min-width:0;
        display:grid;
        grid-template-columns:72px minmax(0, 1fr);
        gap:8px;
        padding:8px 12px;
        border-bottom:1px solid var(--color-border-secondary);
      }
      .ccw-stat:last-child { border-bottom:0; }
      .ccw-stat-k {
        color:var(--color-text-tertiary);
        font-size:11px;
      }
      .ccw-stat-v {
        color:var(--color-text-primary);
        font-size:12px;
        font-weight:700;
        white-space:nowrap;
        overflow:hidden;
        text-overflow:ellipsis;
      }
      .ccw-result {
        white-space:pre-wrap;
        word-break:break-word;
        color:var(--color-text-secondary);
        font-size:12px;
      }
      .ccw-links {
        display:grid;
        gap:6px;
        margin-top:10px;
      }
      .ccw-links a {
        color:var(--color-accent-primary);
        text-decoration:none;
        word-break:break-all;
        font-size:12px;
      }
      .ccw-versions {
        display:grid;
        gap:6px;
        margin-top:10px;
      }
      .ccw-version-row {
        min-width:0;
        display:grid;
        grid-template-columns:minmax(0, 1fr) auto auto;
        gap:6px;
        align-items:center;
        padding:6px 7px;
        border:1px solid var(--color-border-secondary);
        border-radius:6px;
        background:var(--color-bg-primary);
      }
      .ccw-version-main {
        min-width:0;
        display:flex;
        flex-direction:column;
        gap:1px;
      }
      .ccw-version-main strong {
        font-size:11px;
        color:var(--color-text-secondary);
        white-space:nowrap;
        overflow:hidden;
        text-overflow:ellipsis;
      }
      .ccw-version-main span {
        font-size:10px;
        color:var(--color-text-tertiary);
        white-space:nowrap;
        overflow:hidden;
        text-overflow:ellipsis;
      }
      .ccw-lower {
        min-height:0;
        display:grid;
        grid-template-columns:minmax(280px, .8fr) minmax(420px, 1.35fr);
        gap:12px;
        overflow:hidden;
      }
      .ccw-transcript,
      .ccw-timeline {
        min-width:0;
        min-height:0;
        border:1px solid var(--color-border-secondary);
        border-radius:8px;
        background:var(--color-bg-secondary);
        display:grid;
        grid-template-rows:auto minmax(0, 1fr);
        overflow:hidden;
      }
      .ccw-transcript-list {
        min-height:0;
        overflow:auto;
        padding:10px 12px;
        display:flex;
        flex-wrap:wrap;
        gap:5px;
        align-content:flex-start;
      }
      .ccw-word {
        max-width:100%;
        border:1px solid var(--color-border-secondary);
        border-radius:5px;
        background:var(--color-bg-primary);
        color:var(--color-text-secondary);
        padding:2px 6px;
        font-size:11px;
        cursor:pointer;
      }
      .ccw-word:hover {
        border-color:var(--color-accent-primary);
        color:var(--color-accent-primary);
      }
      .ccw-segment-list {
        min-height:0;
        overflow:auto;
        padding:10px 12px;
        display:grid;
        gap:7px;
        align-content:start;
      }
      .ccw-segment {
        min-width:0;
        display:grid;
        grid-template-columns:auto minmax(0,1fr) auto;
        gap:8px;
        align-items:center;
        padding:7px 8px;
        border:1px solid var(--color-border-secondary);
        border-radius:6px;
        background:var(--color-bg-primary);
      }
      .ccw-segment.is-cut {
        border-color:rgba(239,68,68,.45);
        background:color-mix(in srgb, #ef4444 8%, var(--color-bg-primary));
      }
      .ccw-segment.is-cut .ccw-segment-text {
        color:var(--color-text-tertiary);
        text-decoration:line-through;
      }
      .ccw-segment-time {
        color:var(--color-text-tertiary);
        font-size:10px;
        white-space:nowrap;
      }
      .ccw-segment-text {
        min-width:0;
        color:var(--color-text-secondary);
        font-size:12px;
        line-height:1.35;
        overflow:hidden;
        display:-webkit-box;
        -webkit-line-clamp:2;
        -webkit-box-orient:vertical;
      }
      .ccw-caption-edit {
        min-width:0;
        width:100%;
        min-height:34px;
        resize:vertical;
        border:1px solid var(--color-border-secondary);
        border-radius:5px;
        background:var(--color-bg-secondary);
        color:var(--color-text-primary);
        padding:5px 7px;
        font:12px/1.35 var(--font-sans,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif);
      }
      .ccw-caption-edit:focus {
        outline:none;
        border-color:var(--color-accent-primary);
      }
      .ccw-segment-actions {
        display:flex;
        gap:5px;
      }
      .ccw-mini {
        height:24px;
        padding:0 7px;
        border:1px solid var(--color-border-secondary);
        border-radius:5px;
        background:var(--color-bg-secondary);
        color:var(--color-text-secondary);
        font-size:11px;
        cursor:pointer;
      }
      .ccw-mini:hover {
        border-color:var(--color-accent-primary);
        color:var(--color-accent-primary);
      }
      .ccw-mini.danger:hover {
        border-color:#ef4444;
        color:#ef4444;
      }
      .ccw-mini:disabled {
        opacity:.48;
        cursor:not-allowed;
      }
      .ccw-mini.safe:hover {
        border-color:#16a34a;
        color:#16a34a;
      }
      .ccw-timeline-body {
        min-height:0;
        overflow:auto;
        padding:12px;
        display:grid;
        grid-template-rows:auto auto auto;
        gap:10px;
      }
      .ccw-timebar {
        height:22px;
        position:relative;
        border-bottom:1px solid var(--color-border-secondary);
        color:var(--color-text-tertiary);
        font-size:10px;
      }
      .ccw-time-tick {
        position:absolute;
        top:0;
        transform:translateX(-50%);
        white-space:nowrap;
      }
      .ccw-track {
        display:grid;
        grid-template-columns:72px minmax(0, 1fr);
        gap:8px;
        align-items:center;
      }
      .ccw-track-name {
        color:var(--color-text-tertiary);
        font-size:11px;
        font-weight:760;
      }
      .ccw-track-lane {
        height:34px;
        border:1px solid var(--color-border-secondary);
        border-radius:6px;
        background:var(--color-bg-tertiary);
        position:relative;
        overflow:hidden;
      }
      .ccw-clip {
        position:absolute;
        top:6px;
        bottom:6px;
        min-width:2px;
        border-radius:4px;
        opacity:.86;
      }
      .ccw-wave {
        position:absolute;
        inset:7px 8px;
        display:flex;
        align-items:center;
        gap:2px;
      }
      .ccw-wave span {
        flex:1;
        max-width:7px;
        min-width:2px;
        border-radius:2px;
        background:rgba(22,163,74,.7);
      }
      .ccw-playhead {
        position:absolute;
        top:0;
        bottom:0;
        width:2px;
        background:#ef4444;
        z-index:5;
        pointer-events:none;
      }
      .ccw-empty {
        min-height:0;
        display:flex;
        align-items:center;
        justify-content:center;
        padding:18px;
        color:var(--color-text-tertiary);
        text-align:center;
      }
      .ccw-env {
        grid-column:1 / -1;
        min-height:0;
        border:1px solid var(--color-border-secondary);
        border-radius:8px;
        background:var(--color-bg-secondary);
        padding:14px;
        overflow:auto;
      }
      .ccw-env-list {
        display:grid;
        gap:8px;
        margin:10px 0 12px;
      }
      .ccw-env-row {
        display:grid;
        grid-template-columns:150px minmax(0, 1fr);
        gap:10px;
        align-items:center;
        padding:8px 10px;
        border:1px solid var(--color-border-secondary);
        border-radius:6px;
        background:var(--color-bg-primary);
      }
      .ccw-env-name {
        font-weight:740;
      }
      .ccw-env-value {
        min-width:0;
        color:var(--color-text-tertiary);
        white-space:nowrap;
        overflow:hidden;
        text-overflow:ellipsis;
      }
      @media (max-width: 980px) {
        .ccw-root {
          height:auto;
          min-height:720px;
          overflow:visible;
          grid-template-rows:auto auto auto;
        }
        .ccw-topbar,
        .ccw-upper,
        .ccw-lower {
          display:flex;
          flex-direction:column;
          overflow:visible;
        }
        .ccw-preview { min-height:320px; }
        .ccw-side,
        .ccw-transcript,
        .ccw-timeline { min-height:220px; }
        .ccw-status { max-width:none; }
      }
    `;

  mountWorkspace("main.workspace", "main", 20);
  mountWorkspace("session.banner", "banner", 30);
  restoreAnyHostComposers();

  function mountWorkspace(slot, name, order) {
    Clacky.ext.ui.mount(slot, () => {
      const root = el("div", { class: "ccw-root ccw-slot-" + name });
      root.dataset.ccwSlot = name;
      if (name === "banner") root.classList.add("ccw-fallback-hidden");
      const render = () => {
        renderWorkspace(root);
        updateWorkspaceVisibilitySoon();
      };
      trackRenderer(render);
      render();
      ensureEnv();
      updateWorkspaceVisibilitySoon();
      return root;
    }, { order: order });
  }

  function updateWorkspaceVisibilitySoon() {
    setTimeout(updateWorkspaceVisibility, 0);
    if (window.requestAnimationFrame) window.requestAnimationFrame(updateWorkspaceVisibility);
  }

  function updateWorkspaceVisibility() {
    const mainRoots = Array.from(document.querySelectorAll('.ccw-root[data-ccw-slot="main"]'));
    const hasVisibleMain = mainRoots.some((root) => {
      if (!root.isConnected) return false;
      const style = window.getComputedStyle(root);
      return style.display !== "none" && style.visibility !== "hidden" && root.getClientRects().length > 0;
    });
    document.querySelectorAll('.ccw-root[data-ccw-slot="banner"]').forEach((root) => {
      root.classList.toggle("ccw-fallback-hidden", hasVisibleMain);
    });
  }

  function restoreAnyHostComposers() {
    document.querySelectorAll('[data-chatcutpro-hidden-composer="1"]').forEach((node) => {
      restoreHostComposer(node);
    });
  }

  function restoreHostComposer(node) {
    node.style.display = node.dataset.chatcutproPrevDisplay || "";
    delete node.dataset.chatcutproHiddenComposer;
    delete node.dataset.chatcutproPrevDisplay;
  }

  function renderWorkspace(root) {
    root.replaceChildren();
    root.appendChild(renderTopbar());

    if (S.view === "loading") {
      const env = el("div", { class: "ccw-env" });
      env.appendChild(el("div", { class: "ccw-panel-title", text: "正在检测剪辑环境" }));
      env.appendChild(el("div", { class: "ccw-muted", text: "检测 FFmpeg、Python、转写和自动剪辑依赖。" }));
      root.appendChild(env);
      root.appendChild(renderLower());
      return;
    }

    if (S.view === "env_setup") {
      root.appendChild(renderEnvSetup());
      root.appendChild(renderLower());
      return;
    }

    root.appendChild(renderUpper());
    root.appendChild(renderLower());
  }

  function renderTopbar() {
    const bar = el("div", { class: "ccw-topbar" });
    const title = el("div", { class: "ccw-title" });
    title.appendChild(el("strong", { text: "ChatCutPro 剪辑台" }));
    title.appendChild(el("span", { text: S.projectId ? (S.videoFile || S.projectId) : "剪辑工作台，原生对话区执行指令" }));
    bar.appendChild(title);

    const file = document.createElement("input");
    file.type = "file";
    file.accept = "video/*";
    file.style.display = "none";
    file.onchange = () => { if (file.files.length) uploadVideo(file.files[0]); };
    bar.appendChild(file);

    const toolbar = el("div", { class: "ccw-toolbar" });
    toolbar.appendChild(toolButton("上传视频", () => file.click(), { primary: !S.projectId }));
    toolbar.appendChild(toolButton("生成字幕", () => runCommand("生成字幕"), { disabled: !canEdit() }));
    toolbar.appendChild(toolButton("场景检测", () => runCommand("检测场景"), { disabled: !canEdit() }));
    toolbar.appendChild(toolButton("找高光", () => runCommand("找高光"), { disabled: !canEdit() }));
    toolbar.appendChild(toolButton("删停顿", () => runCommand("删停顿"), { disabled: !canEdit() }));
    toolbar.appendChild(toolButton("删口癖", () => runCommand("删口癖"), { disabled: !canEdit() }));
    toolbar.appendChild(toolButton("降噪", () => runCommand("降噪"), { disabled: !canEdit() }));
    toolbar.appendChild(toolButton("统一音量", () => runCommand("统一音量"), { disabled: !canEdit() }));
    toolbar.appendChild(toolButton("加 BGM", () => runCommand("加背景音乐"), { disabled: !canEdit() }));
    toolbar.appendChild(toolButton("配音", () => runCommand("配音 " + defaultVoiceoverText()), { disabled: !canEdit() }));
    toolbar.appendChild(toolButton("加 B-roll", () => runCommand("加 B-roll " + defaultBrollText()), { disabled: !canEdit() }));
    toolbar.appendChild(toolButton("自动精剪", () => runCommand("一键精剪"), { disabled: !canEdit() }));
    toolbar.appendChild(toolButton("HyperFrames 动效", () => runCommand("加 HyperFrames lower third 动效"), { disabled: !canEdit() }));
    toolbar.appendChild(toolButton("导出竖版", () => runCommand("导出竖版"), { disabled: !canEdit() }));
    toolbar.appendChild(toolButton("导出横版", () => runCommand("导出横版"), { disabled: !canEdit() }));
    toolbar.appendChild(toolButton("撤销裁剪", undoLastCut, { disabled: !canUndoCut() }));
    toolbar.appendChild(toolButton("回滚", () => runCommand("回滚上一步"), { disabled: !canEdit() }));
    bar.appendChild(toolbar);

    bar.appendChild(el("div", { class: "ccw-status", text: S.busy ? "执行中：" + (S.status || "") : (S.status || statusText()) }));
    return bar;
  }

  function renderUpper() {
    const upper = el("div", { class: "ccw-upper" });
    upper.appendChild(renderPreview());
    upper.appendChild(renderInspector());
    return upper;
  }

  function renderPreview() {
    const preview = el("div", { class: "ccw-preview" });
    const file = document.createElement("input");
    file.type = "file";
    file.accept = "video/*";
    file.style.display = "none";
    file.onchange = () => { if (file.files.length) uploadVideo(file.files[0]); };
    preview.appendChild(file);

    if (S.videoSrc) {
      const video = el("video", { controls: "controls", preload: "metadata" });
      video.src = S.videoSrc;
      video.ontimeupdate = () => syncVideoUi(video, preview);
      video.onloadedmetadata = () => syncVideoUi(video, preview);
      preview.appendChild(video);
    } else {
      const drop = el("div", { class: "ccw-drop" });
      drop.appendChild(el("div", { class: "ccw-frame-mark", text: "16:9" }));
      drop.appendChild(el("div", { style: "font-weight:760;", text: S.uploading ? "正在上传视频" : "拖放或点击上传视频" }));
      drop.appendChild(el("div", { class: "ccw-muted", text: "MP4 / MOV / WebM / AVI / MKV" }));
      drop.onclick = () => file.click();
      drop.ondragover = (event) => { event.preventDefault(); drop.classList.add("drag"); };
      drop.ondragleave = () => drop.classList.remove("drag");
      drop.ondrop = (event) => {
        event.preventDefault();
        drop.classList.remove("drag");
        if (event.dataTransfer.files.length) uploadVideo(event.dataTransfer.files[0]);
      };
      preview.appendChild(drop);
    }

    const overlay = el("div", { class: "ccw-caption-overlay" });
    overlay.appendChild(el("div", { class: "ccw-caption-text", text: "" }));
    preview.appendChild(overlay);
    return preview;
  }

  function renderInspector() {
    const side = el("div", { class: "ccw-side" });
    const head = el("div", { class: "ccw-panel-head" });
    head.appendChild(el("div", { class: "ccw-panel-title", text: "项目状态" }));
    head.appendChild(el("div", { class: "ccw-muted", text: S.projectId ? S.projectId : "未创建项目" }));
    side.appendChild(head);

    const stats = el("div", { class: "ccw-stats" });
    const timeline = S.timeline || {};
    stats.appendChild(stat("素材", S.videoFile || "等待上传"));
    stats.appendChild(stat("时长", timeline.duration ? formatDurationPair(timeline) : "待分析"));
    stats.appendChild(stat("版本", "v" + (S.currentVersion || 0)));
    stats.appendChild(stat("场景", `${(S.scenes || []).length} 段`));
    stats.appendChild(stat("高光", `${(S.highlights || []).length} 段`));
    stats.appendChild(stat("裁剪", `${cutCount()} 处`));
    stats.appendChild(stat("动效", `${motionClips(timelineDuration()).length} 段`));
    stats.appendChild(stat("B-roll", `${visualTimelineClips("V2", timelineDuration(), "#22c55e").length} 段`));
    stats.appendChild(stat("音频轨", audioStatus()));
    stats.appendChild(stat("状态", S.busy ? "执行中" : statusText()));
    stats.appendChild(stat("HyperFrames", hyperframesStatus()));
    side.appendChild(stats);

    const body = el("div", { class: "ccw-panel-body" });
    renderBeginnerFlow(body);
    if (S.lastResult) {
      body.appendChild(el("div", { class: "ccw-result", text: S.lastResult }));
    } else {
      body.appendChild(el("div", { class: "ccw-muted", text: S.projectId ? "在原生对话区说剪辑意图，这里同步显示结果。" : "先上传视频，工作台会生成可预览、可回滚的剪辑项目。" }));
    }
    renderVersionPanel(body);
    renderMediaLinks(body);
    side.appendChild(body);
    return side;
  }

  function renderBeginnerFlow(parent) {
    const wrap = el("div", { class: "ccw-beginner" });
    wrap.appendChild(el("div", { class: "ccw-muted", text: beginnerHint() }));
    const actions = el("div", { class: "ccw-beginner-actions" });
    actions.appendChild(actionButton("开始", beginnerStart, { primary: !S.projectId }));
    actions.appendChild(actionButton("精剪", () => runCommand("一键精剪"), { disabled: !canEdit() }));
    actions.appendChild(actionButton("导出", () => runCommand("导出竖版，导出横版，导出全部"), { disabled: !canEdit() }));
    wrap.appendChild(actions);
    parent.appendChild(wrap);
  }

  function renderLower() {
    const lower = el("div", { class: "ccw-lower" });
    lower.appendChild(renderTranscript());
    lower.appendChild(renderTimeline());
    return lower;
  }

  function renderTranscript() {
    const panel = el("div", { class: "ccw-transcript" });
    const head = el("div", { class: "ccw-panel-head" });
    head.appendChild(el("div", { class: "ccw-panel-title", text: "字幕 / Transcript" }));
    head.appendChild(el("div", { class: "ccw-muted", text: transcriptHint() }));
    head.appendChild(el("div", { class: "ccw-panel-spacer" }));
    const undo = el("button", { class: "ccw-mini safe", text: "撤销裁剪" });
    undo.disabled = !canUndoCut();
    undo.onclick = undoLastCut;
    head.appendChild(undo);
    panel.appendChild(head);

    const list = el("div", { class: "ccw-segment-list" });
    const words = S.transcript && S.transcript.words;
    const segments = S.transcript && S.transcript.segments;
    if (S.captions && S.captions.length) {
      S.captions.slice(0, 220).forEach((cap, index) => list.appendChild(captionRow(cap, index)));
    } else if (segments && segments.length) {
      segments.slice(0, 180).forEach((seg) => list.appendChild(segmentRow(seg)));
    } else if (words && words.length) {
      list.className = "ccw-transcript-list";
      words.slice(0, 640).forEach((w) => list.appendChild(wordButton(w.word || "", Number(w.start || 0))));
    } else {
      list.appendChild(el("div", { class: "ccw-muted", text: "生成字幕或自动精剪后，逐字稿会在这里按时间戳展开。" }));
    }
    panel.appendChild(list);
    return panel;
  }

  function renderTimeline() {
    const panel = el("div", { class: "ccw-timeline" });
    const head = el("div", { class: "ccw-panel-head" });
    head.appendChild(el("div", { class: "ccw-panel-title", text: "时间线 / Audio" }));
    head.appendChild(el("div", { class: "ccw-muted", text: `MG / V2 / Highlights / V1 / A1 / MUS / VO / Captions · ${cutCount()} cuts` }));
    panel.appendChild(head);

    const body = el("div", { class: "ccw-timeline-body" });
    const duration = timelineDuration();
    body.appendChild(renderTimebar(duration));
    body.appendChild(track("MG", motionClips(duration), duration));
    body.appendChild(track("V2", visualTimelineClips("V2", duration, "#22c55e"), duration));
    body.appendChild(track("HIGH", highlightClips(duration), duration));
    body.appendChild(track("V1", videoTrackClips(duration), duration));
    body.appendChild(audioTrack("A1", duration));
    body.appendChild(track("MUS", audioTimelineClips("MUS", duration, "#16a34a"), duration));
    body.appendChild(track("VO", audioTimelineClips("VO", duration, "#0ea5e9"), duration));
    body.appendChild(track("CAPTIONS", (S.captions || []).map((c) => ({
      start: Number(c.start || 0),
      end: Number(c.end || 0),
      color: "#f59e0b",
    })), duration));
    panel.appendChild(body);
    return panel;
  }

  function renderEnvSetup() {
    const wrap = el("div", { class: "ccw-env" });
    wrap.appendChild(el("div", { class: "ccw-panel-title", text: "环境依赖未就绪" }));
    wrap.appendChild(el("div", { class: "ccw-muted", text: "ChatCut 需要本地 FFmpeg、Python 和转写/剪辑依赖才能处理视频。" }));

    const list = el("div", { class: "ccw-env-list" });
    [
      ["ffmpeg", "FFmpeg", "视频处理"],
      ["python3", "Python 3", "运行环境"],
      ["faster_whisper", "faster-whisper", "语音转写"],
      ["auto_editor", "auto-editor", "删停顿"],
      ["node22", "Node.js 22+", "HyperFrames 运行时"],
      ["hyperframes", "HyperFrames", "HTML 动效渲染"],
    ].forEach(([key, name, desc]) => {
      const check = S.env && S.env.checks && S.env.checks[key];
      const row = el("div", { class: "ccw-env-row" });
      row.appendChild(el("div", { class: "ccw-env-name", text: name }));
      row.appendChild(el("div", { class: "ccw-env-value", text: `${desc}: ${check && check.ok ? (check.version || "OK") : "未安装"}` }));
      list.appendChild(row);
    });
    wrap.appendChild(list);

    const actions = el("div", { style: "display:flex;gap:8px;flex-wrap:wrap;" });
    actions.appendChild(toolButton("自动安装", autoInstall, { primary: true, disabled: S.busy }));
    actions.appendChild(toolButton("重新检测", () => checkEnv(true), { disabled: S.busy }));
    wrap.appendChild(actions);

    if (S.lastResult) {
      const result = el("div", { class: "ccw-result", style: "margin-top:12px;", text: S.lastResult });
      wrap.appendChild(result);
    }
    return wrap;
  }

  async function ensureEnv() {
    if (S.envChecked) return;
    S.envChecked = true;
    await checkEnv(false);
  }

  async function checkEnv(force) {
    if (force) {
      S.view = "loading";
      S.status = "环境检测中";
      S.projectAutoLoaded = false;
      renderAll();
    }
    try {
      const out = await api("GET", "/env_check");
      S.env = out;
      if (out.ready) {
        if (!S.projectId) await loadLatestProject();
        S.view = S.projectId ? "editor" : "upload";
        S.status = S.projectId ? "就绪" : "等待上传";
      } else {
        S.view = "env_setup";
        S.status = "环境未就绪";
      }
    } catch (error) {
      S.env = { error: error.message };
      S.view = "env_setup";
      S.status = "环境检测失败";
      S.lastResult = "环境检测失败：" + error.message;
    }
    renderAll();
  }

  async function loadLatestProject() {
    if (S.projectAutoLoaded || S.projectLoading) return;
    S.projectAutoLoaded = true;
    S.projectLoading = true;
    S.status = "恢复最近项目";
    renderAll();
    try {
      const projects = await api("GET", "/projects");
      const latest = (projects || []).slice().sort((a, b) => String(b.created_at || "").localeCompare(String(a.created_at || "")))[0];
      if (latest && latest.id) {
        const project = await api("GET", "/project/" + encodeURIComponent(latest.id));
        hydrateProject(project);
        if (!S.lastResult) S.lastResult = "已恢复最近项目：" + (S.videoFile || S.projectId);
      }
    } catch (error) {
      S.lastResult = "恢复最近项目失败：" + error.message;
    }
    S.projectLoading = false;
  }

  function hydrateProject(project) {
    if (!project || !project.id) return;
    const video = project.assets && project.assets.video && project.assets.video[0];
    S.projectId = project.id;
    S.videoFile = (video && (video.filename || video.path)) || project.name || project.id;
    S.timeline = project.timeline || S.timeline;
    S.currentVersion = project.current_version || 0;
    S.versions = project.versions || S.versions || [];
    S.media = project.media || S.media;
    S.transcript = project.transcript || S.transcript;
    S.captions = project.captions || S.captions || [];
    S.scenes = (project.media_index && project.media_index.scenes) || project.scenes || S.scenes || [];
    S.highlights = (project.media_index && project.media_index.highlights) || project.highlights || S.highlights || [];
    S.motionGraphics = project.motion_graphics || S.motionGraphics || [];
    S.editDecisions = project.edit_decisions || S.editDecisions || [];
    if (S.media && S.media.latest_video_url) {
      S.videoSrc = S.media.latest_video_url;
    } else {
      S.videoSrc = "/api/ext/chatcut-editor/media/" + encodeURIComponent(project.id) + "/latest?t=" + Date.now();
    }
  }

  async function autoInstall() {
    S.busy = true;
    S.status = "自动安装中";
    renderAll();
    try {
      await api("POST", "/auto_install", {});
      await checkEnv(true);
    } catch (error) {
      S.lastResult = "自动安装失败：" + error.message;
    }
    S.busy = false;
    renderAll();
  }

  async function uploadVideo(file) {
    S.uploading = true;
    S.status = "上传中";
    S.videoFile = file.name;
    S.lastResult = "";
    renderAll();

    if (S.localVideoUrl) URL.revokeObjectURL(S.localVideoUrl);
    S.localVideoUrl = URL.createObjectURL(file);
    S.videoSrc = S.localVideoUrl;

    const form = new FormData();
    form.append("video", file);
    try {
      const out = await fetch("/api/ext/chatcut-editor/upload", { method: "POST", body: form }).then((r) => r.json());
      if (!out.project_id) throw new Error(out.error || "上传失败");
      S.projectId = out.project_id;
      S.videoFile = out.video_file || file.name;
      S.timeline = { duration: out.duration || 0, effective_duration: out.duration || 0 };
      S.currentVersion = 0;
      S.versions = [];
      S.versionDiff = null;
      S.scenes = [];
      S.highlights = [];
      S.view = "editor";
      S.status = "就绪";
      S.media = out.media || S.media;
      S.projectAutoLoaded = true;
      S.lastResult = `项目已创建\n文件：${S.videoFile}\n时长：${out.duration_str || "未知"}\n\n在原生对话区继续说剪辑需求，工作台会同步显示预览、字幕和时间线。`;
    } catch (error) {
      S.view = "upload";
      S.status = "上传失败";
      S.lastResult = "上传失败：" + error.message;
    }
    S.uploading = false;
    renderAll();
  }

  async function runCommand(text) {
    const command = String(text || "").trim();
    if (!command || S.busy) return;
    if (!S.projectId) {
      S.lastResult = "请先在主剪辑台上传视频。";
      S.status = "等待上传";
      renderAll();
      return;
    }

    S.busy = true;
    S.status = command;
    S.lastResult = `正在执行：${command}`;
    renderAll();

    try {
      const out = await api("POST", "/command", { project_id: S.projectId, command });
      applyCommandResult(out);
      S.status = out.state === "error" ? "出错" : "就绪";
    } catch (error) {
      S.lastResult = "请求失败：" + error.message;
      S.status = "请求失败";
    }
    S.busy = false;
    renderAll();
  }

  function applyCommandResult(out) {
    if (!out) return;
    if (out.message) S.lastResult = out.message;
    if (out.transcript) S.transcript = out.transcript;
    if (out.captions) S.captions = out.captions;
    if (out.scenes) S.scenes = out.scenes;
    if (out.highlights) S.highlights = out.highlights;
    if (out.media_index) {
      S.scenes = out.media_index.scenes || S.scenes || [];
      S.highlights = out.media_index.highlights || S.highlights || [];
    }
    if (out.timeline) S.timeline = out.timeline;
    if (out.motion_graphics) S.motionGraphics = out.motion_graphics;
    if (out.edit_decisions) S.editDecisions = out.edit_decisions;
    if (out.version != null) S.currentVersion = out.version;
    if (out.versions) S.versions = out.versions;
    S.versionDiff = null;
    if (out.suggestions) S.suggestions = out.suggestions;
    if (out.media) {
      S.media = out.media;
      if (out.media.latest_video_url) S.videoSrc = out.media.latest_video_url;
    }
    if (out.state === "error" && out.error) S.lastResult = out.error;
  }

  function renderMediaLinks(parent) {
    const exports = (S.media && S.media.exports) || [];
    const generated = (S.media && S.media.generated) || [];
    if (!exports.length && !generated.length) return;
    const links = el("div", { class: "ccw-links" });
    exports.concat(generated).forEach((out) => {
      links.appendChild(el("a", { href: out.url, target: "_blank", text: out.name || out.url }));
    });
    parent.appendChild(links);
  }

  function renderVersionPanel(parent) {
    const versions = (S.versions || []).slice().sort((a, b) => Number(b.version_id || 0) - Number(a.version_id || 0));
    if (!S.projectId || !versions.length) return;

    const box = el("div", { class: "ccw-versions" });
    const head = el("div", { style: "display:flex;align-items:center;gap:6px;" });
    head.appendChild(el("div", { class: "ccw-panel-title", text: "版本" }));
    head.appendChild(el("div", { class: "ccw-panel-spacer" }));
    const diff = el("button", { class: "ccw-mini", text: "对比上版" });
    diff.disabled = S.busy || Number(S.currentVersion || 0) <= 0;
    diff.onclick = diffPreviousVersion;
    head.appendChild(diff);
    box.appendChild(head);

    if (S.versionDiff && S.versionDiff.summary) {
      box.appendChild(el("div", { class: "ccw-result", text: S.versionDiff.summary }));
    }

    versions.slice(0, 4).forEach((version) => {
      const id = Number(version.version_id || 0);
      const row = el("div", { class: "ccw-version-row" });
      const main = el("div", { class: "ccw-version-main" });
      main.appendChild(el("strong", { text: `v${id} ${version.label || "版本"}` }));
      main.appendChild(el("span", { text: version.created_at || "" }));
      row.appendChild(main);
      row.appendChild(el("span", { class: "ccw-muted", text: id === Number(S.currentVersion || 0) ? "当前" : "" }));
      const rollback = el("button", { class: "ccw-mini", text: "回到" });
      rollback.disabled = S.busy || id === Number(S.currentVersion || 0);
      rollback.onclick = () => rollbackVersion(id);
      row.appendChild(rollback);
      box.appendChild(row);
    });
    parent.appendChild(box);
  }

  async function diffPreviousVersion() {
    if (!S.projectId || S.busy || Number(S.currentVersion || 0) <= 0) return;
    S.busy = true;
    S.status = "对比版本";
    renderAll();
    try {
      const toVersion = Number(S.currentVersion || 0);
      const out = await api("POST", "/version/diff", { project_id: S.projectId, from_version: toVersion - 1, to_version: toVersion });
      S.versionDiff = out;
      S.lastResult = out.summary || "版本对比完成";
      S.status = "就绪";
    } catch (error) {
      S.lastResult = "版本对比失败：" + error.message;
      S.status = "对比失败";
    }
    S.busy = false;
    renderAll();
  }

  async function rollbackVersion(versionId) {
    if (!S.projectId || S.busy) return;
    S.busy = true;
    S.status = "回滚版本";
    S.lastResult = `正在回到 v${versionId}`;
    renderAll();
    try {
      const out = await api("POST", "/version/rollback", { project_id: S.projectId, version_id: versionId });
      if (out.timeline) S.timeline = out.timeline;
      if (out.version != null) S.currentVersion = out.version;
      if (out.versions) S.versions = out.versions;
      if (out.edit_decisions) S.editDecisions = out.edit_decisions;
      if (out.media) {
        S.media = out.media;
        if (out.media.latest_video_url) S.videoSrc = out.media.latest_video_url;
      }
      S.versionDiff = null;
      S.lastResult = `已回到 v${versionId}，预览已刷新。`;
      S.status = "就绪";
    } catch (error) {
      S.lastResult = "回滚失败：" + error.message;
      S.status = "回滚失败";
    }
    S.busy = false;
    renderAll();
  }

  function syncVideoUi(video, preview) {
    const current = currentCaption(video.currentTime);
    const caption = preview.querySelector(".ccw-caption-text");
    if (caption) caption.textContent = current ? current.text : "";
    const pct = video.duration ? (video.currentTime / video.duration) * 100 : 0;
    document.querySelectorAll(".ccw-playhead").forEach((node) => { node.style.left = `${pct}%`; });
  }

  function currentCaption(time) {
    return (S.captions || []).find((c) => time >= Number(c.start || 0) && time <= Number(c.end || 0));
  }

  function seekPreview(time) {
    const video = document.querySelector(".ccw-preview video");
    if (!video) return;
    video.currentTime = time;
    video.play().catch(() => {});
  }

  function wordButton(text, start) {
    const button = el("button", { class: "ccw-word", text: text || "" });
    button.onclick = () => seekPreview(start);
    return button;
  }

  function captionRow(cap, index) {
    const start = Number(cap.start || 0);
    const end = Number(cap.end || start);
    const row = el("div", { class: "ccw-segment" });
    row.appendChild(el("div", { class: "ccw-segment-time", text: `${fmtTime(start)}-${fmtTime(end)}` }));
    const input = el("textarea", { class: "ccw-caption-edit" });
    input.value = cap.text || "";
    input.oninput = () => updateCaptionText(index, input.value);
    row.appendChild(input);
    const actions = el("div", { class: "ccw-segment-actions" });
    const play = el("button", { class: "ccw-mini", text: "播放" });
    play.onclick = () => seekPreview(start);
    actions.appendChild(play);
    row.appendChild(actions);
    return row;
  }

  function updateCaptionText(index, text) {
    const cap = (S.captions || [])[index];
    if (!cap) return;
    cap.text = text;
    syncVisibleCaptionText();
    scheduleCaptionSave(index);
  }

  function syncVisibleCaptionText() {
    const video = document.querySelector(".ccw-preview video");
    const caption = document.querySelector(".ccw-preview .ccw-caption-text");
    if (!video || !caption) return;
    const current = currentCaption(video.currentTime);
    caption.textContent = current ? current.text : "";
  }

  function scheduleCaptionSave(index) {
    S.captionSaveTimers = S.captionSaveTimers || {};
    clearTimeout(S.captionSaveTimers[index]);
    S.captionSaveTimers[index] = setTimeout(() => saveCaption(index), 700);
  }

  async function saveCaption(index) {
    const cap = (S.captions || [])[index];
    if (!cap || !S.projectId) return;
    try {
      const out = await api("POST", "/caption/update", {
        project_id: S.projectId,
        caption_id: cap.id,
        index,
        text: cap.text || "",
        start: Number(cap.start || 0),
        end: Number(cap.end || 0),
      });
      if (out.captions) S.captions = out.captions;
      if (out.timeline) S.timeline = out.timeline;
      if (out.media) {
        S.media = out.media;
        if (out.media.latest_video_url) S.videoSrc = out.media.latest_video_url;
      }
      S.status = "字幕已保存";
    } catch (error) {
      S.lastResult = "字幕保存失败：" + error.message;
      S.status = "字幕保存失败";
    }
    renderAll();
  }

  function segmentRow(seg) {
    const start = Number(seg.start || 0);
    const end = Number(seg.end || start);
    const isCut = segmentIsCut(start, end);
    const row = el("div", { class: "ccw-segment" + (isCut ? " is-cut" : "") });
    row.appendChild(el("div", { class: "ccw-segment-time", text: `${fmtTime(start)}-${fmtTime(end)}` }));
    row.appendChild(el("div", { class: "ccw-segment-text", text: seg.text || "" }));
    const actions = el("div", { class: "ccw-segment-actions" });
    const play = el("button", { class: "ccw-mini", text: "播放" });
    play.onclick = () => seekPreview(start);
    actions.appendChild(play);
    const cut = el("button", { class: "ccw-mini danger", text: isCut ? "已裁" : "裁掉" });
    cut.disabled = S.busy || !canEdit() || isCut;
    cut.onclick = () => cutTranscriptSegment(seg);
    actions.appendChild(cut);
    row.appendChild(actions);
    return row;
  }

  async function cutTranscriptSegment(seg) {
    if (!S.projectId || S.busy) return;
    const start = Number(seg.start || 0);
    const end = Number(seg.end || start);
    if (!(end > start)) return;

    S.busy = true;
    S.status = "裁剪 transcript 段落";
    S.lastResult = `正在裁掉 ${fmtTime(start)}-${fmtTime(end)}：${seg.text || ""}`;
    renderAll();
    try {
      const out = await api("POST", "/timeline/cut", {
        project_id: S.projectId,
        start,
        end,
        reason: "manual transcript cut: " + (seg.text || "").slice(0, 80),
      });
      if (out.timeline) S.timeline = out.timeline;
      if (out.version != null) S.currentVersion = out.version;
      if (out.versions) S.versions = out.versions;
      if (out.edit_decisions) S.editDecisions = out.edit_decisions;
      S.versionDiff = null;
      if (out.media) {
        S.media = out.media;
        if (out.media.latest_video_url) S.videoSrc = out.media.latest_video_url;
      }
      S.lastResult = `已裁掉 ${fmtTime(start)}-${fmtTime(end)}。版本 v${S.currentVersion}，预览已重渲染。`;
      S.status = "就绪";
    } catch (error) {
      S.lastResult = "裁剪失败：" + error.message;
      S.status = "裁剪失败";
    }
    S.busy = false;
    renderAll();
  }

  async function undoLastCut() {
    if (!S.projectId || S.busy || !canUndoCut()) return;
    S.busy = true;
    S.status = "撤销最近裁剪";
    S.lastResult = "正在撤销最近一次裁剪并重渲染预览";
    renderAll();
    try {
      const out = await api("POST", "/timeline/undo_last_cut", { project_id: S.projectId });
      if (out.timeline) S.timeline = out.timeline;
      if (out.version != null) S.currentVersion = out.version;
      if (out.versions) S.versions = out.versions;
      if (out.edit_decisions) S.editDecisions = out.edit_decisions;
      S.versionDiff = null;
      if (out.media) {
        S.media = out.media;
        if (out.media.latest_video_url) S.videoSrc = out.media.latest_video_url;
      }
      S.lastResult = `已撤销最近一次裁剪。当前版本 v${S.currentVersion}，预览已刷新。`;
      S.status = "就绪";
    } catch (error) {
      S.lastResult = "撤销裁剪失败：" + error.message;
      S.status = "撤销失败";
    }
    S.busy = false;
    renderAll();
  }

  function renderTimebar(duration) {
    const bar = el("div", { class: "ccw-timebar" });
    const steps = 4;
    for (let i = 0; i <= steps; i += 1) {
      const tick = el("span", { class: "ccw-time-tick", text: fmtTime((duration / steps) * i) });
      tick.style.left = `${(i / steps) * 100}%`;
      bar.appendChild(tick);
    }
    return bar;
  }

  function track(label, clips, duration) {
    const row = el("div", { class: "ccw-track" });
    row.appendChild(el("div", { class: "ccw-track-name", text: label }));
    const lane = el("div", { class: "ccw-track-lane" });
    (clips || []).forEach((clip) => {
      if (!duration) return;
      const node = el("div", { class: "ccw-clip" });
      const left = clamp((Number(clip.start || 0) / duration) * 100, 0, 100);
      const width = clamp(((Number(clip.end || 0) - Number(clip.start || 0)) / duration) * 100, .25, 100);
      node.style.left = `${left}%`;
      node.style.width = `${width}%`;
      node.style.background = clip.color || "var(--color-accent-primary)";
      if (clip.title) node.title = clip.title;
      node.onclick = () => seekPreview(Number(clip.start || 0));
      lane.appendChild(node);
    });
    lane.appendChild(el("span", { class: "ccw-playhead" }));
    row.appendChild(lane);
    return row;
  }

  function audioTrack(label, duration) {
    const row = el("div", { class: "ccw-track" });
    row.appendChild(el("div", { class: "ccw-track-name", text: label }));
    const lane = el("div", { class: "ccw-track-lane" });
    const wave = el("div", { class: "ccw-wave" });
    for (let i = 0; i < 64; i += 1) {
      const bar = document.createElement("span");
      const h = 18 + Math.round((Math.sin(i * 1.7) + 1) * 28) + (i % 5) * 3;
      bar.style.height = `${Math.min(92, h)}%`;
      wave.appendChild(bar);
    }
    lane.appendChild(wave);
    if (duration) {
      lane.appendChild(el("span", { class: "ccw-playhead" }));
    }
    row.appendChild(lane);
    return row;
  }

  function motionClips(duration) {
    const timelineTrack = timelineTrackById("MG");
    const clips = (timelineTrack && timelineTrack.clips && timelineTrack.clips.length ? timelineTrack.clips : S.motionGraphics) || [];
    if (!clips.length) return [];
    return clips.map((clip) => ({
      start: Number(clip.start || 0),
      end: Number(clip.start || 0) + Number(clip.duration || Math.min(5, duration || 5)),
      color: "#8b5cf6",
    }));
  }

  function videoTrackClips(duration) {
    const clips = [{ start: 0, end: duration, color: "var(--color-accent-primary)" }];
    timelineCutRegions("V1").forEach((cut) => {
      clips.push({ start: cut.start, end: cut.end, color: "#ef4444", title: cut.reason || "cut" });
    });
    return clips;
  }

  function highlightClips(duration) {
    return (S.highlights || []).map((h) => {
      const start = Number(h.start || 0);
      const end = Number(h.end || start);
      return {
        start,
        end: end > start ? end : start + Math.min(3, duration || 3),
        color: "#eab308",
        title: h.reason || h.text_preview || "highlight",
      };
    });
  }

  function visualTimelineClips(trackId, duration, color) {
    const trackData = timelineTrackById(trackId);
    const clips = (trackData && trackData.clips) || [];
    return clips.filter((clip) => clip.active !== false).map((clip) => {
      const start = Number(clip.timeline_start != null ? clip.timeline_start : (clip.start || 0));
      const end = Number(clip.end != null ? clip.end : (start + Number(clip.out || clip.duration || Math.min(4, duration || 4))));
      return {
        start,
        end: end > start ? end : start + Math.min(4, duration || 4),
        color,
        title: clip.filename || clip.prompt || trackId,
      };
    });
  }

  function audioTimelineClips(trackId, duration, color) {
    const trackData = timelineTrackById(trackId);
    const clips = (trackData && trackData.clips) || [];
    return clips.filter((clip) => clip.active !== false).map((clip) => {
      const start = Number(clip.timeline_start != null ? clip.timeline_start : (clip.start || 0));
      const end = Number(clip.end != null ? clip.end : (start + Number(clip.out || duration || 0)));
      return {
        start,
        end: end > start ? end : start + Math.min(5, duration || 5),
        color,
        title: clip.filename || clip.text || trackId,
      };
    });
  }

  function timelineCutRegions(trackId) {
    const track = timelineTrackById(trackId);
    const regions = [];
    (track && track.clips || []).forEach((clip) => {
      (clip.cut_regions || []).forEach((region) => {
        const start = Number(region.start || 0);
        const end = Number(region.end || start);
        if (end > start) regions.push({ start, end, reason: region.reason || "" });
      });
    });
    return regions;
  }

  function timelineTrackById(trackId) {
    const tracks = (S.timeline && S.timeline.tracks) || [];
    return tracks.find((t) => t.id === trackId);
  }

  function segmentIsCut(start, end) {
    return timelineCutRegions("V1").some((cut) => rangesOverlap(start, end, cut.start, cut.end));
  }

  function rangesOverlap(aStart, aEnd, bStart, bEnd) {
    return aStart < bEnd - 0.02 && aEnd > bStart + 0.02;
  }

  function cutCount() {
    return timelineCutRegions("V1").length;
  }

  function stat(k, v) {
    const row = el("div", { class: "ccw-stat" });
    row.appendChild(el("div", { class: "ccw-stat-k", text: k }));
    row.appendChild(el("div", { class: "ccw-stat-v", text: v || "无" }));
    return row;
  }

  function toolButton(text, onClick, opts) {
    const button = el("button", { class: "ccw-tool" + (opts && opts.primary ? " primary" : ""), text });
    button.disabled = !!(opts && opts.disabled) || S.busy;
    button.onclick = onClick;
    return button;
  }

  function actionButton(text, onClick, opts) {
    const button = el("button", { class: "ccw-action" + (opts && opts.primary ? " primary" : ""), text });
    button.disabled = !!(opts && opts.disabled) || S.busy;
    button.onclick = onClick;
    return button;
  }

  function beginnerStart() {
    if (!S.projectId) {
      const input = document.querySelector(".ccw-preview input[type='file']");
      if (input) input.click();
      return;
    }
    if (!(S.transcript && S.transcript.segments && S.transcript.segments.length)) {
      runCommand("生成字幕");
      return;
    }
    runCommand("找高光");
  }

  function beginnerHint() {
    if (!S.projectId) return "先放入视频";
    if (!(S.transcript && S.transcript.segments && S.transcript.segments.length)) return "下一步：生成字幕";
    if (!(S.highlights && S.highlights.length)) return "下一步：找高光";
    if (!cutCount()) return "下一步：精剪";
    return "下一步：导出";
  }

  function canEdit() {
    return !!S.projectId && S.view !== "env_setup" && !S.uploading;
  }

  function canUndoCut() {
    return canEdit() && cutCount() > 0;
  }

  function timelineDuration() {
    return Number((S.timeline && S.timeline.duration) || (S.transcript && S.transcript.duration) || 60);
  }

  function transcriptHint() {
    if (S.transcript && S.transcript.words && S.transcript.words.length) return `${S.transcript.words.length} words`;
    if (S.transcript && S.transcript.segments && S.transcript.segments.length) return `${S.transcript.segments.length} segments`;
    return "等待转写";
  }

  function statusText() {
    if (S.view === "env_setup") return "环境未就绪";
    if (S.view === "upload") return "等待上传";
    return S.projectId ? "就绪" : "等待上传";
  }

  function hyperframesStatus() {
    const env = S.env || {};
    if (env.hyperframes_ready) return "可用";
    const checks = env.checks || {};
    if (checks.node22 && checks.node22.ok && checks.npx && checks.npx.ok) return "可自动安装";
    return "待安装";
  }

  function audioStatus() {
    const mus = audioTimelineClips("MUS", timelineDuration(), "#16a34a").length;
    const vo = audioTimelineClips("VO", timelineDuration(), "#0ea5e9").length;
    if (!mus && !vo) return "未添加";
    return `MUS ${mus} / VO ${vo}`;
  }

  function defaultVoiceoverText() {
    const seg = S.transcript && S.transcript.segments && S.transcript.segments[0];
    if (seg && seg.text) return String(seg.text).slice(0, 80);
    return S.videoFile ? `欢迎观看 ${S.videoFile}` : "欢迎观看这条视频";
  }

  function defaultBrollText() {
    const seg = S.transcript && S.transcript.segments && S.transcript.segments[1];
    if (seg && seg.text) return String(seg.text).slice(0, 60);
    return S.videoFile ? S.videoFile.replace(/\.[^.]+$/, "") : "补充画面";
  }

  function formatDurationPair(timeline) {
    const duration = Number(timeline.duration || 0);
    const effective = Number(timeline.effective_duration || 0);
    if (effective && Math.abs(effective - duration) > .05) return `${fmtTime(duration)} -> ${fmtTime(effective)}`;
    return fmtTime(duration);
  }

  function trackRenderer(render) {
    S.renderers.add(render);
  }

  function renderAll() {
    Array.from(S.renderers || []).forEach((render) => {
      try { render(); } catch (_error) {}
    });
  }

  async function api(method, path, body) {
    const opts = { method, headers: { "Content-Type": "application/json" } };
    if (body) opts.body = JSON.stringify(body);
    const res = await fetch("/api/ext/chatcut-editor" + path, opts);
    if (!res.ok) {
      let msg = "HTTP " + res.status;
      try {
        const out = await res.json();
        msg = out.error || out.message || msg;
      } catch (_error) {}
      throw new Error(msg);
    }
    return res.json();
  }

  function el(tag, attrs) {
    const node = document.createElement(tag);
    Object.entries(attrs || {}).forEach(([key, value]) => {
      if (key === "class") node.className = value;
      else if (key === "text") node.textContent = value;
      else if (key === "style") node.style.cssText = value;
      else if (key === "disabled") node.disabled = !!value;
      else node.setAttribute(key, value);
    });
    return node;
  }

  function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
  }

  function fmtTime(seconds) {
    const s = Number(seconds || 0);
    const m = Math.floor(s / 60);
    const rest = Math.max(0, s - m * 60);
    return `${m}:${rest.toFixed(1).padStart(4, "0")}`;
  }
})();
