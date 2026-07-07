# frozen_string_literal: true

require "json"
require "fileutils"
require "securerandom"
require "open3"
require "shellwords"
require "time"
require "timeout"

class ChatcutEditorHandler < Clacky::ApiExtension
  timeout 120

  PROJECTS_DIR = File.expand_path("~/.clacky/chatcut_projects")

  # ════════════════════════════════════════════════════════════════
  # 环境检测 + 自动安装
  # ════════════════════════════════════════════════════════════════

  get "/env_check" do
    json(env_check_result)
  end

  post "/auto_install" do
    results = []
    pip_deps = { "faster_whisper" => "faster-whisper", "auto_editor" => "auto-editor" }

    pip_deps.each do |mod, pkg|
      unless python_module_ok?(mod)
        out, _, status = Open3.capture3("pip3 install #{pkg} 2>&1")
        results << { target: pkg, success: status.success?, output: out.lines.last(3).join }
      end
    end

    unless command_ok?("ffmpeg")
      if File.exist?(File.expand_path("~/bin/ffmpeg"))
        results << { target: "ffmpeg", success: true, output: "已在 ~/bin/ffmpeg" }
      else
        results << { target: "ffmpeg", success: false, manual_required: true }
      end
    end

    if node22_ok? && command_ok?("npx")
      begin
        out, _, status = Timeout.timeout(120) { Open3.capture3("#{resolve_cmd('npx')} --yes hyperframes --version 2>&1") }
        results << { target: "hyperframes", success: status.success?, output: out.lines.last(6).join }
      rescue Timeout::Error
        results << { target: "hyperframes", success: false, output: "HyperFrames 安装检测超时，可稍后重试。" }
      end
    else
      results << { target: "hyperframes", success: false, manual_required: true, output: "需要 Node.js 22+ 和 npx。" }
    end

    json(results: results, final_status: env_check_result)
  end

  # ════════════════════════════════════════════════════════════════
  # 项目管理
  # ════════════════════════════════════════════════════════════════

  # POST /upload — 接收 { file_path: "/path/to/video.mp4" }
  # 前端先通过 /api/upload 上传拿到 path，再调这个接口初始化项目
  post "/upload" do
    # 支持两种方式: multipart form 或 JSON body with file_path
    file_path = nil
    filename = nil

    content_type_header = req["Content-Type"].to_s
    if content_type_header.include?("multipart/form-data")
      upload = parse_multipart(req)
      if upload
        # 保存到项目目录
        project_id = SecureRandom.hex(8)
        project_dir = File.join(PROJECTS_DIR, project_id)
        FileUtils.mkdir_p(File.join(project_dir, "versions"))
        FileUtils.mkdir_p(File.join(project_dir, "generated"))
        FileUtils.mkdir_p(File.join(project_dir, "exports"))
        FileUtils.mkdir_p(File.join(project_dir, "export_bundle"))
        file_path = File.join(project_dir, upload[:filename])
        File.open(file_path, "wb") { |f| f.write(upload[:data]) }
        filename = upload[:filename]
      end
    else
      body = json_body
      file_path = body["file_path"]
      filename = File.basename(file_path.to_s)
      project_id = SecureRandom.hex(8)
      project_dir = File.join(PROJECTS_DIR, project_id)
      FileUtils.mkdir_p(File.join(project_dir, "versions"))
      FileUtils.mkdir_p(File.join(project_dir, "generated"))
      FileUtils.mkdir_p(File.join(project_dir, "exports"))
      FileUtils.mkdir_p(File.join(project_dir, "export_bundle"))
      # Copy or symlink the file into project dir
      if file_path && File.exist?(file_path)
        dest = File.join(project_dir, filename)
        FileUtils.cp(file_path, dest) unless File.identical?(file_path, dest) rescue nil
        file_path = dest
      end
    end

    error!("No video file provided", status: 400) unless file_path && File.exist?(file_path)

    probe = probe_video(file_path)

    project = {
      "id" => project_id,
      "name" => File.basename(filename.to_s, ".*"),
      "created_at" => Time.now.iso8601,
      "updated_at" => Time.now.iso8601,
      "assets" => {
        "video" => [{ "path" => file_path, "filename" => filename, "duration" => probe[:duration], "resolution" => probe[:resolution], "fps" => probe[:fps], "codec" => probe[:codec] }],
        "audio" => [], "image" => [], "generated" => [],
      },
      "media_index" => { "transcript" => nil, "speakers" => [], "silences" => [], "fillers" => [], "scenes" => [], "highlights" => [], "keyframes" => [] },
      "timeline" => init_timeline(probe),
      "edit_decisions" => [],
      "patches" => [],
      "versions" => [],
      "current_version" => 0,
      "steps_completed" => [],
      "state" => "ready",
    }
    snapshot_version(project_dir, project, "初始状态", nil)

    save_project(project_dir, project)

    json(
      project_id: project_id,
      duration: probe[:duration],
      duration_str: probe[:duration_str],
      resolution: probe[:resolution],
      fps: probe[:fps],
      video_file: filename,
      media: media_links(project)
    )
  end

  get "/project/:id" do
    project = load_project(params[:id])
    error!("Not found", status: 404) unless project
    data = JSON.parse(JSON.generate(project))
    data["media"] = media_links(project)
    transcript_path = project.dig("media_index", "transcript")
    data["transcript"] = JSON.parse(File.read(transcript_path)) if transcript_path && File.file?(transcript_path)
    caption_track = project.dig("timeline", "tracks")&.find { |t| t["id"] == "CAPTIONS" }
    data["captions"] = (caption_track && caption_track["clips"]) || []
    data["motion_graphics"] = motion_graphics_for_ui(project)
    json(data)
  end

  get "/projects" do
    return json([]) unless File.directory?(PROJECTS_DIR)
    list = Dir.glob(File.join(PROJECTS_DIR, "*")).map do |d|
      next unless File.directory?(d)
      meta = File.join(d, "project.json")
      next unless File.exist?(meta)
      p = JSON.parse(File.read(meta))
      { id: p["id"], name: p["name"], state: p["state"], created_at: p["created_at"], duration: p.dig("assets", "video", 0, "duration") }
    end.compact
    json(list)
  end

  post "/plan" do
    body = json_body
    project_id = body["project_id"] || latest_project_id
    command = body["command"]
    error!("Missing command", status: 400) unless command

    project = load_project(project_id)
    error!("Project not found", status: 404) unless project

    json(plan_execution(command, project))
  end

  # ════════════════════════════════════════════════════════════════
  # Agent Loop 入口
  # ════════════════════════════════════════════════════════════════

  post "/command" do
    body = json_body
    project_id = body["project_id"]
    command = body["command"]

    error!("Missing command", status: 400) unless command
    project_id ||= latest_project_id

    pdir = File.join(PROJECTS_DIR, project_id)
    error!("Project not found", status: 404) unless File.directory?(pdir)

    project = load_project(project_id)
    video_path = project.dig("assets", "video", 0, "path")

    # 环境预检
    env = env_check_result
    unless env[:ready]
      json(state: "env_error", message: "⚠️ 环境未就绪\n缺少：#{env[:missing].join('、')}\n\n请点击「自动安装」或手动安装后重试。", missing: env[:missing])
    end

    # Agent Loop: READ → PLAN → EXECUTE → REVIEW
    plan = plan_execution(command, project)
    execution = execute_plan(plan, pdir, video_path, project)

    project["updated_at"] = Time.now.iso8601
    project["state"] = execution[:has_error] ? "error" : "done"
    save_project(pdir, project)

    json(assemble_response(plan, execution, project))
  end

  # ════════════════════════════════════════════════════════════════
  # Timeline Patch Engine
  # ════════════════════════════════════════════════════════════════

  post "/patch" do
    body = json_body
    project_id = body["project_id"]
    patch = body["patch"]
    error!("Missing project_id or patch", status: 400) unless project_id && patch

    pdir = File.join(PROJECTS_DIR, project_id)
    project = load_project(project_id)
    error!("Project not found", status: 404) unless project

    apply_patch_to_project(project, patch)
    save_project(pdir, project)

    json(success: true, version: project["current_version"], timeline: project["timeline"])
  end

  post "/timeline/cut" do
    body = json_body
    project_id = body["project_id"] || latest_project_id
    start_time = body["start"].to_f
    end_time = body["end"].to_f
    reason = body["reason"].to_s.strip

    error!("Invalid cut range", status: 422) unless end_time > start_time && start_time >= 0

    pdir = project_dir_for(project_id)
    project = load_project(project_id)
    error!("Project not found", status: 404) unless project

    patch = {
      "op" => "cut_segments",
      "track" => "V1",
      "segments" => [{ "start" => start_time.round(3), "end" => end_time.round(3), "reason" => reason.empty? ? "manual transcript cut" : reason }],
      "created_by" => "manual-transcript-editor",
    }
    apply_patch_to_project(project, patch)
    render = render_timeline_video(pdir, project)
    save_project(pdir, project)

    json(
      success: true,
      patch: patch,
      version: project["current_version"],
      versions: project["versions"],
      timeline: timeline_for_ui(project),
      media: media_links(project),
      render: render,
      edit_decisions: (project["edit_decisions"] || []).last(12)
    )
  end

  post "/timeline/undo_last_cut" do
    body = json_body
    project_id = body["project_id"] || latest_project_id
    pdir = project_dir_for(project_id)
    project = load_project(project_id)
    error!("Project not found", status: 404) unless project

    cut_patch = latest_active_cut_patch(project)
    error!("No cut to undo", status: 422) unless cut_patch

    removed = undo_cut_patch(project, cut_patch)
    error!("Cut could not be undone", status: 422) unless removed.positive?

    render = render_timeline_video(pdir, project)
    save_project(pdir, project)

    json(
      success: true,
      undone_patch_id: cut_patch["id"],
      removed_regions: removed,
      version: project["current_version"],
      versions: project["versions"],
      timeline: timeline_for_ui(project),
      media: media_links(project),
      render: render,
      edit_decisions: (project["edit_decisions"] || []).last(12)
    )
  end

  post "/caption/update" do
    body = json_body
    project_id = body["project_id"] || latest_project_id
    pdir = project_dir_for(project_id)
    project = load_project(project_id)
    error!("Project not found", status: 404) unless project

    caption_id = body["caption_id"].to_s
    index = body["index"]
    text = body["text"].to_s
    start_time = body.key?("start") ? body["start"].to_f : nil
    end_time = body.key?("end") ? body["end"].to_f : nil

    caption = update_caption_clip(project, caption_id, index, text, start_time, end_time)
    error!("Caption not found", status: 404) unless caption

    captions = captions_for_project(project)
    rewrite_caption_files(pdir, captions)
    render = render_timeline_video(pdir, project)
    save_project(pdir, project)

    json(
      success: true,
      caption: caption,
      captions: captions,
      timeline: timeline_for_ui(project),
      media: media_links(project),
      render: render
    )
  end

  post "/version/save" do
    body = json_body
    project = load_project(body["project_id"])
    error!("Not found", status: 404) unless project

    label = body["label"] || "手动保存"
    save_version(project, label)
    save_project(project_dir_for(body["project_id"]), project)

    json(success: true, version_id: project["current_version"], versions: project["versions"])
  end

  post "/version/rollback" do
    body = json_body
    project = load_project(body["project_id"])
    error!("Not found", status: 404) unless project

    target_version = body["version_id"] || (project["current_version"] - 1)
    rollback_to_version(project, target_version)
    pdir = project_dir_for(body["project_id"])
    render = render_timeline_video(pdir, project)
    save_project(pdir, project)

    json(
      success: true,
      rolled_back_to: target_version,
      version: project["current_version"],
      versions: project["versions"],
      timeline: timeline_for_ui(project),
      media: media_links(project),
      render: render,
      edit_decisions: (project["edit_decisions"] || []).last(12)
    )
  end

  get "/versions/:project_id" do
    project = load_project(params[:project_id])
    error!("Not found", status: 404) unless project
    json(current: project["current_version"], versions: project["versions"])
  end

  post "/version/diff" do
    body = json_body
    project_id = body["project_id"] || latest_project_id
    project = load_project(project_id)
    error!("Not found", status: 404) unless project

    to_version = (body["to_version"] || project["current_version"]).to_i
    from_version = (body["from_version"] || to_version - 1).to_i
    error!("Invalid version range", status: 422) if from_version < 0 || to_version < 0

    json(version_diff(project, from_version, to_version))
  end

  post "/export_bundle" do
    body = json_body
    project_id = body["project_id"] || latest_project_id
    project = load_project(project_id)
    error!("Not found", status: 404) unless project

    pdir = project_dir_for(project_id)
    bundle = build_export_bundle(pdir, project)
    save_project(pdir, project)
    json(bundle)
  end

  get "/media/:project_id/:file" do
    project = load_project(params[:project_id])
    error!("Not found", status: 404) unless project

    path = media_path_for(project, params[:file])
    error!("file not found", status: 404) unless path && File.file?(path)

    res["Content-Disposition"] = %(inline; filename="#{File.basename(path)}")
    raise Clacky::ApiExtension::Halt.new(200, File.binread(path), mime_for(path))
  end

  private

  # ════════════════════════════════════════════════════════════════
  # Multipart parser (for file upload)
  # ════════════════════════════════════════════════════════════════

  def parse_multipart(request)
    ct = request["Content-Type"].to_s
    return nil unless ct.include?("multipart/form-data")

    boundary_match = ct.match(/boundary=([^\s;]+)/)
    return nil unless boundary_match

    boundary = "--" + boundary_match[1].strip.gsub(/^"(.*)"$/, '\1')
    body = request.body.to_s.b

    parts = body.split(Regexp.new(Regexp.escape(boundary)))
    parts.each do |part|
      header_body_sep = part.index("\r\n\r\n") || part.index("\n\n")
      next unless header_body_sep

      sep_len = part[header_body_sep, 4] == "\r\n\r\n" ? 4 : 2
      raw_headers = part[0, header_body_sep]
      raw_body = part[(header_body_sep + sep_len)..]
      raw_body = raw_body.sub(/\r\n\z/, "").sub(/\n\z/, "")

      next unless raw_headers.include?("Content-Disposition")
      name_match = raw_headers.match(/name="([^"]+)"/)
      next unless name_match && name_match[1] == "video"

      file_match = raw_headers.match(/filename="([^"]*)"/)
      filename = file_match ? file_match[1] : "upload.mp4"

      return { filename: filename, data: raw_body }
    end
    nil
  end

  # ════════════════════════════════════════════════════════════════
  # 环境检测
  # ════════════════════════════════════════════════════════════════

  def env_check_result
    checks = {}
    checks[:ffmpeg] = command_info("ffmpeg", "-version")
    checks[:python3] = command_info("python3", "--version")
    checks[:node22] = node_info
    checks[:npx] = command_info("npx", "--version")
    checks[:hyperframes] = hyperframes_info(checks)
    checks[:faster_whisper] = python_module_info("faster_whisper")
    checks[:auto_editor] = command_info("auto-editor", "--version")

    missing = []
    missing << "FFmpeg" unless checks[:ffmpeg][:ok]
    missing << "Python3" unless checks[:python3][:ok]
    missing << "faster-whisper" unless checks[:faster_whisper][:ok]

    ready = missing.empty?

    guide = []
    unless checks[:ffmpeg][:ok]
      guide << { target: "ffmpeg", title: "FFmpeg（视频处理核心）", command: "curl -L https://www.osxexperts.net/ffmpeg7arm.zip -o /tmp/ffmpeg.zip && mkdir -p ~/bin && unzip -o /tmp/ffmpeg.zip -d ~/bin && chmod +x ~/bin/ffmpeg", auto: false, note: "ARM64 预编译版，无需密码" }
    end
    unless checks[:faster_whisper][:ok]
      guide << { target: "faster_whisper", title: "faster-whisper（语音转写）", command: "pip3 install faster-whisper", auto: true, note: "首次转写自动下载模型" }
    end
    unless checks[:auto_editor][:ok]
      guide << { target: "auto_editor", title: "auto-editor（删停顿）", command: "pip3 install auto-editor", auto: true, note: "可选" }
    end
    unless checks[:node22][:ok]
      guide << { target: "node22", title: "Node.js 22+（HyperFrames 运行时）", command: "mise install node@22 && mise use -g node@22", auto: false, note: "HyperFrames 本地渲染需要 Node.js 22+" }
    end
    unless checks[:hyperframes][:ok]
      guide << { target: "hyperframes", title: "HyperFrames（HTML 动效/视频渲染）", command: "npx --yes hyperframes --version", auto: true, note: "用于 lower third、标题卡、网站转视频等可编辑动效" }
    end

    { ready: ready, missing: missing, checks: checks, install_guide: guide, hyperframes_ready: checks[:hyperframes][:ok] }
  end

  def command_ok?(cmd)
    _, _, status = Open3.capture3(resolve_cmd(cmd) + " --version 2>/dev/null")
    status.success?
  rescue
    false
  end

  def command_available?(cmd)
    system("command -v #{Shellwords.escape(cmd)} >/dev/null 2>&1")
  rescue
    false
  end

  def command_info(cmd, flag)
    full_cmd = resolve_cmd(cmd)
    stdout, _, status = Open3.capture3("#{full_cmd} #{flag} 2>&1")
    { ok: status.success?, version: stdout.lines.first&.strip&.slice(0, 80) }
  rescue Errno::ENOENT
    { ok: false, version: nil }
  end

  # Resolve command including ~/bin fallback (server PATH may not include it)
  def resolve_cmd(cmd)
    home_bin = File.expand_path("~/bin/#{cmd}")
    return home_bin if File.executable?(home_bin)
    local_bin = File.expand_path("~/Library/Python/3.9/bin/#{cmd}")
    return local_bin if File.executable?(local_bin)
    mise_bin = Dir.glob(File.expand_path("~/.local/share/mise/installs/node/*/bin/#{cmd}")).sort.last
    return mise_bin if mise_bin && File.executable?(mise_bin)
    cmd
  end

  def node_info
    stdout, _, status = Open3.capture3("#{resolve_cmd('node')} --version 2>&1")
    version = stdout.lines.first.to_s.strip
    { ok: status.success? && node_version_ok?(version), version: version.empty? ? nil : version }
  rescue
    { ok: false, version: nil }
  end

  def node22_ok?
    node_info[:ok]
  end

  def node_version_ok?(version)
    major = version.to_s[/v?(\d+)/, 1].to_i
    major >= 22
  end

  def hyperframes_info(checks = nil)
    global = command_info("hyperframes", "--version")
    return global if global[:ok]

    checks ||= {}
    node_ok = checks.dig(:node22, :ok)
    npx_ok = checks.dig(:npx, :ok)
    if node_ok && npx_ok
      { ok: true, version: "via npx hyperframes" }
    else
      { ok: false, version: nil }
    end
  end

  def ffmpeg_bin
    @ffmpeg_bin ||= resolve_cmd("ffmpeg")
  end

  def ffprobe_bin
    @ffprobe_bin ||= resolve_cmd("ffprobe")
  end

  def python_module_ok?(mod)
    _, _, status = Open3.capture3("python3 -c \"import #{mod}\" 2>&1")
    status.success?
  rescue
    false
  end

  def python_module_info(mod)
    stdout, _, status = Open3.capture3("python3 -c \"import #{mod}; print(getattr(#{mod}, '__version__', 'ok'))\" 2>&1")
    { ok: status.success?, version: stdout.strip }
  rescue
    { ok: false, version: nil }
  end

  # ════════════════════════════════════════════════════════════════
  # Project Helpers
  # ════════════════════════════════════════════════════════════════

  def init_timeline(probe)
    duration = probe[:duration] || 0
    {
      "duration" => duration,
      "resolution" => { "width" => probe[:width] || 1920, "height" => probe[:height] || 1080 },
      "fps" => probe[:fps] || 30,
      "tracks" => [
        { "id" => "MG", "type" => "motion_graphics", "clips" => [] },
        { "id" => "V2", "type" => "video_overlay", "clips" => [] },
        { "id" => "V1", "type" => "video", "clips" => [{ "id" => "clip_v1_001", "source" => "original", "in" => 0, "out" => duration, "timeline_start" => 0, "active" => true }] },
        { "id" => "A1", "type" => "audio", "clips" => [{ "id" => "clip_a1_001", "source" => "original", "in" => 0, "out" => duration, "timeline_start" => 0, "active" => true }] },
        { "id" => "MUS", "type" => "music", "clips" => [] },
        { "id" => "VO", "type" => "voiceover", "clips" => [] },
        { "id" => "CAPTIONS", "type" => "subtitle", "clips" => [] },
      ],
    }
  end

  def save_project(dir, project)
    project["updated_at"] = Time.now.iso8601
    FileUtils.mkdir_p(dir)
    FileUtils.mkdir_p(File.join(dir, "versions"))
    FileUtils.mkdir_p(File.join(dir, "generated"))
    FileUtils.mkdir_p(File.join(dir, "exports"))
    FileUtils.mkdir_p(File.join(dir, "export_bundle"))
    write_json_file(File.join(dir, "project.json"), project)
    write_json_file(File.join(dir, "timeline.json"), project["timeline"] || {})
    write_json_file(File.join(dir, "edit_decisions.json"), project["edit_decisions"] || [])
    write_json_file(File.join(dir, "patches.json"), project["patches"] || [])
  end

  def write_json_file(path, value)
    tmp = "#{path}.tmp"
    File.write(tmp, JSON.pretty_generate(value))
    FileUtils.mv(tmp, path)
  end

  def load_project(id)
    dir = File.join(PROJECTS_DIR, id.to_s)
    return nil unless File.directory?(dir)
    project = JSON.parse(File.read(File.join(dir, "project.json")))
    normalize_project_state(dir, project)
    project
  end

  def project_dir_for(id)
    File.join(PROJECTS_DIR, id.to_s)
  end

  def normalize_project_state(dir, project)
    project["assets"] ||= { "video" => [], "audio" => [], "image" => [], "generated" => [] }
    project["media_index"] ||= {}
    project["media_index"]["scenes"] ||= []
    project["media_index"]["highlights"] ||= []
    project["edit_decisions"] ||= []
    project["patches"] ||= []
    project["versions"] ||= []
    project["steps_completed"] ||= []
    ensure_timeline_tracks(project)

    current = project["current_version"] || 0
    version = project["versions"].find { |v| v["version_id"].to_i == current.to_i }
    return unless version && !version["timeline_snapshot_path"] && project["timeline"]

    FileUtils.mkdir_p(File.join(dir, "versions"))
    snapshot_file = File.join("versions", "v#{current}_timeline.json")
    write_json_file(File.join(dir, snapshot_file), project["timeline"])
    version["timeline_snapshot_path"] = snapshot_file
  end

  def ensure_timeline_tracks(project)
    project["timeline"] ||= { "duration" => project.dig("assets", "video", 0, "duration").to_f, "tracks" => [] }
    project["timeline"]["tracks"] ||= []
    duration = project["timeline"]["duration"].to_f
    specs = [
      ["MG", "motion_graphics", []],
      ["V2", "video_overlay", []],
      ["V1", "video", [{ "id" => "clip_v1_001", "source" => "original", "in" => 0, "out" => duration, "timeline_start" => 0, "active" => true }]],
      ["A1", "audio", [{ "id" => "clip_a1_001", "source" => "original", "in" => 0, "out" => duration, "timeline_start" => 0, "active" => true }]],
      ["MUS", "music", []],
      ["VO", "voiceover", []],
      ["CAPTIONS", "subtitle", []],
    ]
    specs.each do |id, type, clips|
      track = project["timeline"]["tracks"].find { |t| t["id"] == id }
      if track
        track["type"] ||= type
        track["clips"] ||= []
      else
        project["timeline"]["tracks"] << { "id" => id, "type" => type, "clips" => clips }
      end
    end
    order = specs.map(&:first)
    project["timeline"]["tracks"].sort_by! { |track| order.index(track["id"]) || 99 }
  end

  def latest_project_id
    return nil unless File.directory?(PROJECTS_DIR)
    dirs = Dir.glob(File.join(PROJECTS_DIR, "*")).select { |d| File.directory?(d) && File.exist?(File.join(d, "project.json")) }
    latest = dirs.max_by { |d| File.mtime(File.join(d, "project.json")) rescue Time.at(0) }
    latest && File.basename(latest)
  end

  def media_path_for(project, file)
    project_dir = project_dir_for(project["id"])
    original = project.dig("assets", "video", 0, "path")
    key = File.basename(file.to_s)

    case key
    when "original"
      original
    when "latest"
      latest_video(project_dir, original)
    else
      return nil unless key.match?(/\A[a-zA-Z0-9._-]+\z/)

      [
        File.join(project_dir, key),
        File.join(project_dir, "exports", key),
        File.join(project_dir, "generated", key),
      ].find { |path| File.file?(path) }
    end
  end

  def timeline_for_ui(project)
    timeline = project["timeline"] || {}
    {
      duration: timeline["duration"],
      effective_duration: timeline["effective_duration"],
      tracks: timeline["tracks"],
    }
  end

  def media_url(project, key)
    path = media_path_for(project, key)
    return nil unless path && File.file?(path)

    stamp = File.mtime(path).to_i rescue Time.now.to_i
    "/api/ext/chatcut-editor/media/#{project['id']}/#{File.basename(key)}?t=#{stamp}"
  end

  def media_links(project)
    project_dir = project_dir_for(project["id"])
    exports = Dir.glob(File.join(project_dir, "exports", "*")).select { |path| File.file?(path) }.map do |path|
      {
        name: File.basename(path),
        url: media_url(project, File.basename(path)),
        size_mb: (File.size(path) / 1048576.0).round(1),
      }
    end

    {
      original_video_url: media_url(project, "original"),
      latest_video_url: media_url(project, "latest"),
      exports: exports,
      generated: generated_links(project),
    }
  end

  def generated_links(project)
    project_dir = project_dir_for(project["id"])
    Dir.glob(File.join(project_dir, "generated", "*")).select { |path| File.file?(path) }.map do |path|
      {
        name: File.basename(path),
        url: media_url(project, File.basename(path)),
        size_mb: (File.size(path) / 1048576.0).round(1),
      }
    end
  end

  def mime_for(path)
    case File.extname(path.to_s).downcase
    when ".mp4" then "video/mp4"
    when ".mov" then "video/quicktime"
    when ".webm" then "video/webm"
    when ".mkv" then "video/x-matroska"
    when ".m4a" then "audio/mp4"
    when ".mp3" then "audio/mpeg"
    when ".wav" then "audio/wav"
    when ".aiff", ".aif" then "audio/aiff"
    when ".srt" then "text/plain; charset=utf-8"
    when ".ass" then "text/plain; charset=utf-8"
    when ".json" then "application/json"
    when ".html" then "text/html; charset=utf-8"
    else "application/octet-stream"
    end
  end

  # ════════════════════════════════════════════════════════════════
  # Timeline Patch Engine
  # ════════════════════════════════════════════════════════════════

  def apply_patch_to_project(project, patch)
    patch["id"] ||= "patch_#{SecureRandom.hex(4)}"
    patch["applied_at"] = Time.now.iso8601

    project["patches"] ||= []
    project["patches"] << patch
    project["edit_decisions"] ||= []
    project["edit_decisions"] << edit_decision_for_patch(project, patch)

    case patch["op"]
    when "cut_segments"   then apply_cut_segments(project["timeline"], patch)
    when "add_clip"       then apply_add_clip(project["timeline"], patch)
    when "add_caption"    then apply_add_caption(project["timeline"], patch)
    when "add_motion_graphic" then apply_add_motion_graphic(project["timeline"], patch)
    when "modify_clip"    then apply_modify_clip(project["timeline"], patch)
    end

    snapshot_version(project_dir_for(project["id"]), project, patch_summary(patch), patch["id"])
  end

  def apply_cut_segments(timeline, patch)
    track_id = patch["track"] || "V1"
    segments_to_cut = patch["segments"] || []
    return if segments_to_cut.empty?

    affected_tracks = [track_id]
    affected_tracks << "A1" if track_id == "V1"
    affected_tracks << "V1" if track_id == "A1"

    affected_tracks.uniq.each do |tid|
      t = timeline["tracks"].find { |tr| tr["id"] == tid }
      next unless t
      segments_to_cut.each do |seg|
        t["clips"].each do |clip|
          next unless clip["active"]
          if clip["in"].to_f < seg["end"].to_f && clip["out"].to_f > seg["start"].to_f
            clip["cut_regions"] ||= []
            clip["cut_regions"] << { "start" => seg["start"], "end" => seg["end"], "reason" => seg["reason"], "patch_id" => patch["id"] }
          end
        end
      end
    end

    refresh_effective_duration(timeline)
  end

  def latest_active_cut_patch(project)
    (project["patches"] || []).reverse.find { |patch| patch["op"] == "cut_segments" && !patch["undone_at"] }
  end

  def undo_cut_patch(project, patch)
    timeline = project["timeline"] || {}
    removed = remove_cut_regions_for_patch(timeline, patch)
    return 0 unless removed.positive?

    patch["undone_at"] = Time.now.iso8601
    refresh_effective_duration(timeline)
    project["edit_decisions"] ||= []
    project["edit_decisions"] << {
      "id" => "decision_#{SecureRandom.hex(4)}",
      "patch_id" => patch["id"],
      "op" => "undo_cut",
      "created_by" => "manual-editor",
      "summary" => "撤销最近裁剪",
      "segments" => patch["segments"] || [],
      "saved_seconds" => -((patch["segments"] || []).sum { |s| s["end"].to_f - s["start"].to_f }).round(3),
      "created_at" => Time.now.iso8601,
    }
    snapshot_version(project_dir_for(project["id"]), project, "撤销最近裁剪", nil)
    removed
  end

  def remove_cut_regions_for_patch(timeline, patch)
    segments = patch["segments"] || []
    removed = 0
    (timeline["tracks"] || []).select { |track| %w[V1 A1].include?(track["id"]) }.each do |track|
      (track["clips"] || []).each do |clip|
        before = clip["cut_regions"] || []
        next if before.empty?

        clip["cut_regions"] = before.reject do |region|
          match = region["patch_id"] == patch["id"] || segments.any? { |seg| same_cut_region?(region, seg) }
          removed += 1 if match
          match
        end
      end
    end
    removed
  end

  def same_cut_region?(region, seg)
    (region["start"].to_f - seg["start"].to_f).abs < 0.02 &&
      (region["end"].to_f - seg["end"].to_f).abs < 0.02 &&
      (seg["reason"].to_s.empty? || region["reason"].to_s == seg["reason"].to_s)
  end

  def refresh_effective_duration(timeline)
    duration = timeline["duration"].to_f
    ranges = timeline_cut_ranges_from_timeline(timeline)
    cut_total = ranges.sum { |r| r["end"].to_f - r["start"].to_f }
    timeline["effective_duration"] = [duration - cut_total, 0].max.round(3)
  end

  def apply_add_clip(timeline, patch)
    track_id = patch["track"]
    clip = patch["clip"]
    track = timeline["tracks"].find { |t| t["id"] == track_id }
    return unless track
    clip["id"] ||= "clip_#{SecureRandom.hex(4)}"
    clip["active"] = true
    track["clips"] << clip
  end

  def apply_add_caption(timeline, patch)
    track = timeline["tracks"].find { |t| t["id"] == "CAPTIONS" }
    return unless track
    (patch["captions"] || []).each do |cap|
      track["clips"] << { "id" => "cap_#{SecureRandom.hex(3)}", "start" => cap["start"], "end" => cap["end"], "text" => cap["text"], "style" => cap["style"] || "default", "active" => true }
    end
  end

  def update_caption_clip(project, caption_id, index, text, start_time, end_time)
    track = project.dig("timeline", "tracks")&.find { |t| t["id"] == "CAPTIONS" }
    return nil unless track

    clips = track["clips"] || []
    caption = if !caption_id.empty?
      clips.find { |clip| clip["id"].to_s == caption_id }
    elsif !index.nil?
      clips[index.to_i]
    end
    return nil unless caption

    caption["text"] = text
    caption["start"] = start_time.round(3) if start_time
    caption["end"] = end_time.round(3) if end_time && (!start_time || end_time > caption["start"].to_f)
    caption["updated_at"] = Time.now.iso8601
    caption
  end

  def captions_for_project(project)
    track = project.dig("timeline", "tracks")&.find { |t| t["id"] == "CAPTIONS" }
    ((track && track["clips"]) || [])
      .select { |clip| clip["active"] != false }
      .sort_by { |clip| clip["start"].to_f }
  end

  def rewrite_caption_files(project_dir, captions)
    segments = captions.map do |cap|
      { "start" => cap["start"].to_f, "end" => cap["end"].to_f, "text" => cap["text"].to_s }
    end
    srt = segments.each_with_index.map { |s, i| "#{i + 1}\n#{srt_time(s['start'])} --> #{srt_time(s['end'])}\n#{s['text']}\n" }.join("\n")
    File.write(File.join(project_dir, "captions.srt"), srt)
    ass = generate_ass(segments)
    File.write(File.join(project_dir, "captions.ass"), ass)
    styled_path = File.join(project_dir, "captions_styled.ass")
    if File.file?(styled_path)
      styled = ass.gsub(/^Style: Default,.+$/, "Style: Default,Noto Sans SC Bold,52,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,3,0,2,10,10,40,1")
      File.write(styled_path, styled)
    end
  end

  def apply_add_motion_graphic(timeline, patch)
    track = timeline["tracks"].find { |t| t["id"] == "MG" }
    return unless track
    comp = patch["component"]
    comp["id"] ||= "mg_#{SecureRandom.hex(4)}"
    comp["active"] = true
    track["clips"] << comp
  end

  def apply_modify_clip(timeline, patch)
    track_id = patch["track"]
    clip_id = patch["clip_id"]
    changes = patch["changes"] || {}
    track = timeline["tracks"].find { |t| t["id"] == track_id }
    return unless track
    clip = track["clips"].find { |c| c["id"] == clip_id }
    return unless clip
    changes.each { |k, v| clip[k] = v }
  end

  def save_version(project, label)
    snapshot_version(project_dir_for(project["id"]), project, label, nil)
  end

  def rollback_to_version(project, target_version)
    version = project["versions"].find { |v| v["version_id"] == target_version }
    return unless version
    snapshot_path = version["timeline_snapshot_path"]
    if snapshot_path
      full_path = File.expand_path(snapshot_path, project_dir_for(project["id"]))
      project["timeline"] = JSON.parse(File.read(full_path)) if File.file?(full_path)
    elsif version["timeline_snapshot"]
      project["timeline"] = version["timeline_snapshot"]
    end
    project["current_version"] = target_version
    project["edit_decisions"] ||= []
    project["edit_decisions"] << {
      "id" => "decision_#{SecureRandom.hex(4)}",
      "op" => "rollback",
      "summary" => "回滚到版本 ##{target_version}",
      "version_id" => target_version,
      "created_at" => Time.now.iso8601,
    }
  end

  def version_diff(project, from_version, to_version)
    from_timeline = load_version_timeline(project, from_version)
    to_timeline = load_version_timeline(project, to_version)
    error!("Version snapshot not found", status: 404) unless from_timeline && to_timeline

    from_metrics = timeline_metrics(from_timeline)
    to_metrics = timeline_metrics(to_timeline)
    track_ids = (from_metrics[:tracks].keys + to_metrics[:tracks].keys).uniq.sort
    track_changes = track_ids.map do |track_id|
      before = from_metrics[:tracks][track_id] || { clips: 0, cuts: 0 }
      after = to_metrics[:tracks][track_id] || { clips: 0, cuts: 0 }
      {
        track: track_id,
        clips_before: before[:clips],
        clips_after: after[:clips],
        clips_delta: after[:clips] - before[:clips],
        cuts_before: before[:cuts],
        cuts_after: after[:cuts],
        cuts_delta: after[:cuts] - before[:cuts],
      }
    end

    {
      project_id: project["id"],
      from_version: from_version,
      to_version: to_version,
      duration_before: from_metrics[:effective_duration],
      duration_after: to_metrics[:effective_duration],
      duration_delta: (to_metrics[:effective_duration] - from_metrics[:effective_duration]).round(3),
      cut_count_before: from_metrics[:cut_count],
      cut_count_after: to_metrics[:cut_count],
      cut_count_delta: to_metrics[:cut_count] - from_metrics[:cut_count],
      track_changes: track_changes,
      summary: version_diff_summary(from_version, to_version, from_metrics, to_metrics, track_changes),
    }
  end

  def load_version_timeline(project, version_id)
    version = (project["versions"] || []).find { |v| v["version_id"].to_i == version_id.to_i }
    return project["timeline"] if version_id.to_i == project["current_version"].to_i && project["timeline"]
    return nil unless version

    if version["timeline_snapshot_path"]
      path = File.expand_path(version["timeline_snapshot_path"], project_dir_for(project["id"]))
      return JSON.parse(File.read(path)) if File.file?(path)
    end
    version["timeline_snapshot"]
  rescue
    nil
  end

  def timeline_metrics(timeline)
    tracks = {}
    (timeline["tracks"] || []).each do |track|
      clips = track["clips"] || []
      cuts = clips.sum { |clip| (clip["cut_regions"] || []).length }
      tracks[track["id"]] = { clips: clips.length, cuts: cuts }
    end
    {
      duration: timeline["duration"].to_f,
      effective_duration: (timeline["effective_duration"] || timeline["duration"] || 0).to_f.round(3),
      cut_count: timeline_cut_ranges_from_timeline(timeline).length,
      tracks: tracks,
    }
  end

  def version_diff_summary(from_version, to_version, from_metrics, to_metrics, track_changes)
    parts = ["v#{from_version} -> v#{to_version}"]
    delta = (to_metrics[:effective_duration] - from_metrics[:effective_duration]).round(1)
    parts << (delta.negative? ? "缩短 #{delta.abs}s" : delta.positive? ? "变长 #{delta}s" : "时长不变")
    cut_delta = to_metrics[:cut_count] - from_metrics[:cut_count]
    parts << (cut_delta.positive? ? "新增 #{cut_delta} 处裁剪" : cut_delta.negative? ? "减少 #{cut_delta.abs} 处裁剪" : "裁剪数不变")
    clip_notes = track_changes.select { |c| c[:clips_delta].to_i != 0 }.map do |c|
      delta_value = c[:clips_delta].to_i
      "#{c[:track]} #{delta_value.positive? ? '+' : ''}#{delta_value}"
    end
    parts << "轨道变化：#{clip_notes.join('、')}" if clip_notes.any?
    parts.join("；")
  end

  def snapshot_version(project_dir, project, label, patch_id)
    FileUtils.mkdir_p(File.join(project_dir, "versions"))
    existing_ids = (project["versions"] || []).map { |v| v["version_id"].to_i }
    version_id = if existing_ids.empty?
      0
    else
      existing_ids.max + 1
    end
    project["current_version"] = version_id
    snapshot_file = File.join("versions", "v#{version_id}_timeline.json")
    write_json_file(File.join(project_dir, snapshot_file), project["timeline"] || {})

    project["versions"] ||= []
    project["versions"].reject! { |v| v["version_id"] == version_id }
    project["versions"] << {
      "version_id" => version_id,
      "label" => label,
      "patch_id" => patch_id,
      "patches_applied" => (project["patches"] || []).map { |p| p["id"] }.compact,
      "created_at" => Time.now.iso8601,
      "timeline_snapshot_path" => snapshot_file,
    }
  end

  def edit_decision_for_patch(project, patch)
    segments = patch["segments"] || []
    saved = segments.sum { |s| s["end"].to_f - s["start"].to_f }.round(3)
    {
      "id" => "decision_#{SecureRandom.hex(4)}",
      "patch_id" => patch["id"],
      "op" => patch["op"],
      "created_by" => patch["created_by"],
      "summary" => patch_summary(patch),
      "segments" => segments,
      "saved_seconds" => saved,
      "version_before" => project["current_version"],
      "created_at" => Time.now.iso8601,
    }
  end

  def patch_summary(patch)
    case patch["op"]
    when "cut_segments"  then "删除 #{patch['segments']&.length || 0} 个片段"
    when "add_clip"      then "添加 #{patch['track']} 轨 clip"
    when "add_caption"   then "添加 #{patch['captions']&.length || 0} 条字幕"
    when "add_motion_graphic" then "添加动效"
    when "modify_clip"   then "修改 clip 属性"
    else patch["op"].to_s
    end
  end

  # ════════════════════════════════════════════════════════════════
  # Agent Loop: PLAN
  # ════════════════════════════════════════════════════════════════

  def plan_execution(command, project)
    cmd = command.downcase.strip
    steps = []

    append_steps(steps, plan_full_auto(project)) if cmd.match?(/一键.*剪|精剪|全自动|auto.?edit|全流程/)
    append_steps(steps, plan_with_deps(["transcribe_align", "caption_generate", "caption_style"], project)) if cmd.match?(/生成字幕|字幕|transcribe|caption|加字幕/)
    append_steps(steps, plan_with_deps(["silence_detect", "apply_silence_cut"], project)) if cmd.match?(/删.*停顿|silence|删静音|压缩停顿|tighten/)
    append_steps(steps, plan_with_deps(["transcribe_align", "filler_detect", "apply_filler_cut"], project)) if cmd.match?(/删.*口癖|filler|去口癖|删废话|去嗯啊/)
    append_steps(steps, ["scene_detect"]) if cmd.match?(/检测场景|场景检测|找转场|scene detect|shot detect/)
    append_steps(steps, ["scene_detect", "highlight_extract"]) if cmd.match?(/找高光|切精华|提取亮点|highlight|切片|高光/)
    append_steps(steps, ["audio_denoise"]) if cmd.match?(/降噪|去噪|噪音|电流声|clean audio|denoise/)
    append_steps(steps, ["audio_normalize"]) if cmd.match?(/统一音量|标准化音量|音量.*统一|normalize|loudness|太小|太大/)
    append_steps(steps, ["music_generate"]) if cmd.match?(/加.*背景音乐|背景音乐|配乐|bgm|music bed|music/)
    append_steps(steps, ["voiceover_generate"]) if cmd.match?(/配音|旁白|voiceover|朗读|生成语音|tts/)
    append_steps(steps, ["broll_generate"]) if cmd.match?(/b-?roll|补镜头|插入画面|补画面|加画面|加素材|illustrate/)
    append_steps(steps, ["hyperframes_motion"]) if cmd.match?(/hyperframes|动效|motion|lower.?third|标题卡|title.?card|logo.?reveal|图表|chart|cta|overlay|网站.*视频|网页.*视频/)
    append_steps(steps, ["export_portrait"]) if cmd.match?(/导出.*竖|竖版|9.?16|portrait|reels|tiktok|小红书|抖音/)
    append_steps(steps, ["export_landscape"]) if cmd.match?(/导出.*横|横版|16.?9|landscape|youtube|b站|bilibili/)
    append_steps(steps, ["edit_report", "export_bundle"]) if cmd.match?(/导出全部|打包|交付|export all|bundle|project package/)
    append_steps(steps, ["edit_report"]) if cmd.match?(/报告|report|统计/)
    append_steps(steps, ["rollback"]) if cmd.match?(/回滚|撤销|undo|rollback/)
    append_steps(steps, ["version_info"]) if cmd.match?(/版本|version/)
    steps = ["interpret_and_execute"] if steps.empty?

    { command: command, steps: steps, total: steps.length }
  end

  def append_steps(steps, next_steps)
    next_steps.each do |step|
      steps << step unless steps.include?(step)
    end
  end

  def plan_full_auto(project)
    steps = []
    steps << "transcribe_align" unless project["steps_completed"]&.include?("transcribe_align")
    steps += ["silence_detect", "apply_silence_cut", "filler_detect", "apply_filler_cut", "audio_normalize", "caption_generate", "caption_style", "save_version", "edit_report"]
    steps
  end

  def plan_with_deps(target_steps, project)
    completed = project["steps_completed"] || []
    target_steps.reject { |s| completed.include?(s) && s == "transcribe_align" }
  end

  # ════════════════════════════════════════════════════════════════
  # Agent Loop: EXECUTE
  # ════════════════════════════════════════════════════════════════

  def execute_plan(plan, project_dir, video_path, project)
    results = []
    has_error = false
    current_video = video_path

    plan[:steps].each_with_index do |step, i|
      result = execute_step(step, project_dir, current_video, project, plan[:command])
      results << { step: step, index: i, result: result }

      if result[:error] && result[:blocking]
        has_error = true
        break
      end

      project["steps_completed"] ||= []
      project["steps_completed"] << step unless result[:error]
      current_video = result[:output_file] if result[:output_file] && result[:updates_video]
    end

    { results: results, has_error: has_error }
  end

  def execute_step(step, project_dir, video_path, project, command = nil)
    case step
    when "transcribe_align"   then do_transcribe(project_dir, video_path, project)
    when "silence_detect"     then do_silence_detect(project_dir, video_path, project)
    when "apply_silence_cut"  then do_apply_silence_cut(project_dir, video_path, project)
    when "filler_detect"      then do_filler_detect(project_dir, project)
    when "apply_filler_cut"   then do_apply_filler_cut(project_dir, video_path, project)
    when "scene_detect"       then do_scene_detect(project_dir, video_path, project)
    when "highlight_extract"  then do_highlight_extract(project_dir, project)
    when "caption_generate"   then do_caption_generate(project_dir, project)
    when "caption_style"      then do_caption_style(project_dir, project)
    when "audio_denoise"      then do_audio_denoise(project_dir, project)
    when "audio_normalize"    then do_audio_normalize(project_dir, project)
    when "music_generate"     then do_music_generate(project_dir, project, command.to_s)
    when "voiceover_generate" then do_voiceover_generate(project_dir, project, command.to_s)
    when "broll_generate"     then do_broll_generate(project_dir, project, command.to_s)
    when "export_portrait"    then do_export(project_dir, video_path, project, "9:16")
    when "export_landscape"   then do_export(project_dir, video_path, project, "16:9")
    when "hyperframes_motion"  then do_hyperframes_motion(project_dir, video_path, project, command.to_s)
    when "edit_report"        then do_report(project_dir, project)
    when "export_bundle"       then do_export_bundle(project_dir, project)
    when "save_version"       then do_save_version(project)
    when "rollback"           then do_rollback(project_dir, project)
    when "version_info"       then do_version_info(project)
    when "interpret_and_execute"
      { message: "当前支持的指令：一键精剪 / 找高光 / 检测场景 / 生成字幕 / 删停顿 / 删口癖 / 降噪 / 统一音量 / 加背景音乐 / 配音 / 加 B-roll / HyperFrames 动效 / 导出竖版 / 导出横版 / 回滚 / 剪辑报告", error: false }
    else
      { message: "步骤 #{step} 开发中", error: false }
    end
  end

  # ── 转写 ──────────────────────────────────────────────
  def do_transcribe(project_dir, video_path, project)
    audio_path = File.join(project_dir, "audio.wav")

    _, _, status = Open3.capture3("#{ffmpeg_bin} -y -i \"#{video_path}\" -vn -acodec pcm_s16le -ar 16000 -ac 1 \"#{audio_path}\" 2>&1")
    return { message: "❌ 音频提取失败，请确认 FFmpeg 已安装。", error: true, blocking: true } unless status.success?

    script_path = File.join(project_dir, "_transcribe.py")
    File.write(script_path, build_transcribe_script(audio_path))

    stdout, stderr, status = Open3.capture3("python3 \"#{script_path}\"")
    begin
      transcript = JSON.parse(stdout)
    rescue
      return { message: "❌ 转写失败\n#{stderr.lines.last(3).join}\n请确认 faster-whisper 已安装", error: true, blocking: true }
    end

    return { message: "❌ 转写错误：#{transcript['error']}", error: true, blocking: true } if transcript["error"]

    File.write(File.join(project_dir, "transcript.json"), JSON.pretty_generate(transcript))
    project["media_index"]["transcript"] = File.join(project_dir, "transcript.json")
    project["timeline"]["duration"] = transcript["duration"] if transcript["duration"]

    {
      message: "✅ 转写完成：#{transcript['segments']&.length || 0} 段，#{transcript['words']&.length || 0} 词\n语言：#{transcript['language']}，时长：#{fmt_dur(transcript['duration'])}",
      transcript: transcript,
      error: false,
    }
  end

  # ── 静音检测 ──────────────────────────────────────────
  def do_silence_detect(project_dir, video_path, project)
    output, _, _ = Open3.capture3("#{ffmpeg_bin} -i \"#{video_path}\" -af silencedetect=noise=-30dB:d=0.5 -f null - 2>&1")

    silences = []
    output.scan(/silence_start: ([\d.]+).*?silence_end: ([\d.]+)/m) do |s, e|
      silences << { "start" => s.to_f, "end" => e.to_f, "duration" => (e.to_f - s.to_f).round(3) }
    end

    project["media_index"]["silences"] = silences
    total = silences.sum { |s| s["duration"] }.round(1)

    { message: "✅ 检测到 #{silences.length} 处停顿，总计 #{total}s", error: false }
  end

  # ── 应用静音删除 ──────────────────────────────────────
  def do_apply_silence_cut(project_dir, video_path, project)
    silences = project.dig("media_index", "silences") || []
    return { message: "未检测到停顿，跳过", error: false } if silences.empty?

    patch = {
      "op" => "cut_segments", "track" => "V1",
      "segments" => silences.map { |s| { "start" => s["start"], "end" => s["end"], "reason" => "silence" } },
      "created_by" => "video-silence-cut",
    }
    apply_patch_to_project(project, patch)

    output_path = File.join(project_dir, "silence_cut.mp4")
    if command_ok?("auto-editor")
      _, _, st = Open3.capture3("#{resolve_cmd('auto-editor')} \"#{video_path}\" --no-open --output \"#{output_path}\" 2>&1")
      cut_with_ffmpeg(video_path, silences, output_path, project_dir) unless st.success?
    else
      cut_with_ffmpeg(video_path, silences, output_path, project_dir)
    end
    render_timeline_video(project_dir, project)

    saved = silences.sum { |s| s["end"] - s["start"] }.round(1)
    { message: "✅ 删停顿完成，删除 #{silences.length} 处，节省 #{saved}s", output_file: (File.exist?(output_path) ? output_path : nil), updates_video: true, error: false }
  end

  # ── 口癖检测 ──────────────────────────────────────────
  def do_filler_detect(project_dir, project)
    transcript_path = project.dig("media_index", "transcript")
    return { message: "❌ 需要先转写", error: true, blocking: true } unless transcript_path && File.exist?(transcript_path)

    transcript = JSON.parse(File.read(transcript_path))
    words = transcript["words"] || []
    return { message: "无逐词数据", error: false } if words.empty?

    zh_fillers = %w[嗯 啊 呃 额 那个 就是 然后 对吧 这个 反正 所以说]
    en_fillers = %w[um uh er ah like basically actually]
    filler_regex = Regexp.new("^(#{(zh_fillers + en_fillers).join('|')})$", Regexp::IGNORECASE)

    fillers = words.select { |w| w["word"].strip.match?(filler_regex) }
    project["media_index"]["fillers"] = fillers

    return { message: "✅ 未检测到口癖词", error: false } if fillers.empty?

    top = fillers.map { |w| w["word"].strip }.each_with_object(Hash.new(0)) { |w, h| h[w] += 1 }.sort_by { |_, c| -c }.first(5)
    filler_str = top.map { |w, c| "「#{w}」×#{c}" }.join("  ")
    total = fillers.sum { |w| w["end"].to_f - w["start"].to_f }.round(1)

    { message: "✅ 检测到 #{fillers.length} 处口癖词，总计 #{total}s\n#{filler_str}", error: false }
  end

  # ── 应用口癖删除 ──────────────────────────────────────
  def do_apply_filler_cut(project_dir, video_path, project)
    fillers = project.dig("media_index", "fillers") || []
    return { message: "未检测到口癖，跳过", error: false } if fillers.empty?

    patch = {
      "op" => "cut_segments", "track" => "V1",
      "segments" => fillers.map { |w| { "start" => w["start"], "end" => w["end"], "reason" => "filler: #{w['word']}" } },
      "created_by" => "video-filler-cut",
    }
    apply_patch_to_project(project, patch)

    output_path = File.join(project_dir, "filler_cut.mp4")
    input = latest_video(project_dir, video_path)
    cut_with_ffmpeg(input, fillers.map { |w| { "start" => w["start"], "end" => w["end"] } }, output_path, project_dir)
    render_timeline_video(project_dir, project)

    saved = fillers.sum { |w| w["end"].to_f - w["start"].to_f }.round(1)
    { message: "✅ 删口癖完成，删除 #{fillers.length} 处，节省 #{saved}s", output_file: (File.exist?(output_path) ? output_path : nil), updates_video: true, error: false }
  end

  # ── 场景检测 / 高光粗剪 ──────────────────────────────
  def do_scene_detect(project_dir, video_path, project)
    duration = timeline_render_duration(project)
    duration = probe_duration(video_path).to_f if duration <= 0
    return { message: "❌ 场景检测失败：项目时长未知", error: true, blocking: false } unless duration.positive?

    output, _, = Open3.capture3("#{ffmpeg_bin} -i #{Shellwords.escape(video_path)} -filter:v \"select='gt(scene,0.30)',showinfo\" -f null - 2>&1")
    boundaries = output.scan(/pts_time:([\d.]+)/).flatten.map(&:to_f)
      .select { |t| t > 0.15 && t < duration - 0.15 }
      .uniq
      .sort
    scenes = scene_ranges_from_boundaries(boundaries, duration)
    project["media_index"]["scenes"] = scenes

    { message: "✅ 场景检测完成：#{scenes.length} 段", scenes: scenes, error: false }
  end

  def do_highlight_extract(project_dir, project)
    duration = timeline_render_duration(project)
    return { message: "❌ 高光提取失败：项目时长未知", error: true, blocking: false } unless duration.positive?

    highlights = extract_highlights(project, duration)
    return { message: "未找到可提取的高光片段", highlights: [], error: false } if highlights.empty?

    project["media_index"]["highlights"] = highlights
    cuts = non_highlight_cuts(highlights, duration)
    if cuts.any?
      patch = {
        "op" => "cut_segments",
        "track" => "V1",
        "segments" => cuts,
        "created_by" => "video-highlight-extract",
      }
      apply_patch_to_project(project, patch)
    end
    render = render_timeline_video(project_dir, project)

    total = highlights.sum { |h| h["end"].to_f - h["start"].to_f }.round(1)
    { message: "✅ 高光粗剪完成：#{highlights.length} 段，保留 #{total}s", highlights: highlights, render: render, error: false }
  end

  # ── 字幕生成 ──────────────────────────────────────────
  def do_caption_generate(project_dir, project)
    transcript_path = project.dig("media_index", "transcript")
    return { message: "❌ 需要先转写", error: true, blocking: true } unless transcript_path && File.exist?(transcript_path)

    transcript = JSON.parse(File.read(transcript_path))
    segments = transcript["segments"] || []

    srt_path = File.join(project_dir, "captions.srt")
    srt = segments.each_with_index.map { |s, i| "#{i + 1}\n#{srt_time(s['start'])} --> #{srt_time(s['end'])}\n#{s['text']}\n" }.join("\n")
    File.write(srt_path, srt)

    ass_path = File.join(project_dir, "captions.ass")
    File.write(ass_path, generate_ass(segments))

    patch = { "op" => "add_caption", "captions" => segments.map { |s| { "start" => s["start"], "end" => s["end"], "text" => s["text"] } }, "created_by" => "video-caption-generate" }
    apply_patch_to_project(project, patch)

    captions_for_ui = segments.map { |s| { start: s["start"], end: s["end"], text: s["text"] } }
    { message: "✅ 字幕生成完成：#{segments.length} 条", captions: captions_for_ui, error: false }
  end

  # ── 字幕样式化 ──────────────────────────────────────
  def do_caption_style(project_dir, project)
    ass_path = File.join(project_dir, "captions.ass")
    return { message: "字幕已生成", error: false } unless File.exist?(ass_path)

    styled_path = File.join(project_dir, "captions_styled.ass")
    content = File.read(ass_path)
    styled = content.gsub(/^Style: Default,.+$/, "Style: Default,Noto Sans SC Bold,52,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,3,0,2,10,10,40,1")
    File.write(styled_path, styled)
    render_timeline_video(project_dir, project)

    { message: "✅ 字幕样式化完成（白字黑描边）", error: false }
  end

  # ── 音频处理 / 多轨音频 ──────────────────────────────
  def do_audio_denoise(project_dir, project)
    clip = first_clip(project, "A1")
    return { message: "❌ 没有可处理的人声轨 A1", error: true, blocking: false } unless clip

    processing = (clip["audio_processing"] || {}).merge("denoise" => { "level" => "medium", "filter" => "afftdn" })
    patch = {
      "op" => "modify_clip",
      "track" => "A1",
      "clip_id" => clip["id"],
      "changes" => { "audio_processing" => processing },
      "created_by" => "audio-denoise",
    }
    apply_patch_to_project(project, patch)
    render = render_timeline_video(project_dir, project)
    { message: "✅ 已为 A1 人声轨启用降噪，并刷新预览", render: render, error: false }
  end

  def do_audio_normalize(project_dir, project)
    clip = first_clip(project, "A1")
    return { message: "❌ 没有可处理的人声轨 A1", error: true, blocking: false } unless clip

    processing = (clip["audio_processing"] || {}).merge("normalize" => { "target_lufs" => -16, "true_peak" => -1.5, "lra" => 11 })
    patch = {
      "op" => "modify_clip",
      "track" => "A1",
      "clip_id" => clip["id"],
      "changes" => { "audio_processing" => processing },
      "created_by" => "audio-normalize",
    }
    apply_patch_to_project(project, patch)
    render = render_timeline_video(project_dir, project)
    { message: "✅ 已统一 A1 人声响度到 -16 LUFS，并刷新预览", render: render, error: false }
  end

  def do_music_generate(project_dir, project, command)
    FileUtils.mkdir_p(File.join(project_dir, "generated"))
    duration = timeline_render_duration(project)
    stamp = Time.now.strftime("%Y%m%d_%H%M%S")
    output_path = File.join(project_dir, "generated", "music_bed_#{stamp}.m4a")
    return { message: "❌ 背景音乐生成失败：项目时长未知", error: true, blocking: false } unless duration.positive?

    ok = synth_music_bed(output_path, duration)
    return { message: "❌ 背景音乐生成失败，请确认 FFmpeg 可用", error: true, blocking: false } unless ok

    clip = {
      "id" => "music_#{SecureRandom.hex(4)}",
      "source" => output_path,
      "filename" => File.basename(output_path),
      "in" => 0,
      "out" => duration,
      "timeline_start" => 0,
      "start" => 0,
      "end" => duration,
      "volume" => 0.18,
      "duck_to" => "A1",
      "duck_amount_db" => -12,
      "prompt" => command.to_s.strip,
      "active" => true,
    }
    patch = { "op" => "add_clip", "track" => "MUS", "clip" => clip, "created_by" => "audio-music-generate" }
    apply_patch_to_project(project, patch)
    project["assets"]["audio"] ||= []
    project["assets"]["audio"] << { "path" => output_path, "filename" => File.basename(output_path), "type" => "music_bed", "duration" => duration }
    render = render_timeline_video(project_dir, project)

    { message: "✅ 背景音乐已生成并放入 MUS 轨，已自动压低到人声下面", audio: clip, render: render, error: false }
  end

  def do_voiceover_generate(project_dir, project, command)
    text = voiceover_text(command, project)
    return { message: "❌ 没有可朗读的配音文本", error: true, blocking: false } if text.empty?
    return { message: "❌ 当前系统没有可用的 macOS say，请稍后接入 TTS 服务", error: true, blocking: false } unless command_available?("say")

    FileUtils.mkdir_p(File.join(project_dir, "generated"))
    stamp = Time.now.strftime("%Y%m%d_%H%M%S")
    aiff_path = File.join(project_dir, "generated", "voiceover_#{stamp}.aiff")
    output_path = File.join(project_dir, "generated", "voiceover_#{stamp}.m4a")
    _, stderr, status = Open3.capture3("say", "-o", aiff_path, text)
    return { message: "❌ 配音生成失败：#{stderr.lines.last(2).join.strip}", error: true, blocking: false } unless status.success? && File.file?(aiff_path)

    _, _, convert_status = Open3.capture3("#{ffmpeg_bin} -y -i #{Shellwords.escape(aiff_path)} -c:a aac -b:a 128k #{Shellwords.escape(output_path)} 2>&1")
    FileUtils.rm_f(aiff_path)
    return { message: "❌ 配音转码失败，请确认 FFmpeg 可用", error: true, blocking: false } unless convert_status.success? && File.file?(output_path)

    duration = probe_duration(output_path) || [text.length * 0.22, 2.0].max
    start = 0.0
    clip = {
      "id" => "vo_#{SecureRandom.hex(4)}",
      "source" => output_path,
      "filename" => File.basename(output_path),
      "text" => text,
      "in" => 0,
      "out" => duration,
      "timeline_start" => start,
      "start" => start,
      "end" => start + duration,
      "volume" => 0.95,
      "active" => true,
    }
    patch = { "op" => "add_clip", "track" => "VO", "clip" => clip, "created_by" => "audio-voiceover-generate" }
    apply_patch_to_project(project, patch)
    project["assets"]["audio"] ||= []
    project["assets"]["audio"] << { "path" => output_path, "filename" => File.basename(output_path), "type" => "voiceover", "duration" => duration }
    render = render_timeline_video(project_dir, project)

    { message: "✅ 配音已生成并放入 VO 轨，预览已刷新", audio: clip, render: render, error: false }
  end

  # ── B-roll / V2 覆盖画面 ─────────────────────────────
  def do_broll_generate(project_dir, project, command)
    FileUtils.mkdir_p(File.join(project_dir, "generated"))
    total_duration = timeline_render_duration(project)
    return { message: "❌ 无法生成 B-roll：项目时长未知", error: true, blocking: false } unless total_duration.positive?

    start_time = broll_start_time(project, total_duration)
    clip_duration = [[4.0, total_duration - start_time].min, 1.0].max.round(3)
    stamp = Time.now.strftime("%Y%m%d_%H%M%S")
    output_path = File.join(project_dir, "generated", "broll_#{stamp}.mp4")
    prompt = broll_prompt(command, project)
    ok = synth_broll_video(project_dir, project, output_path, clip_duration, prompt)
    return { message: "❌ B-roll 生成失败，请确认 FFmpeg 可用", error: true, blocking: false } unless ok

    clip = {
      "id" => "broll_#{SecureRandom.hex(4)}",
      "source" => output_path,
      "filename" => File.basename(output_path),
      "prompt" => prompt,
      "source_type" => "local_generated",
      "in" => 0,
      "out" => clip_duration,
      "timeline_start" => start_time,
      "start" => start_time,
      "end" => start_time + clip_duration,
      "fit" => "cover",
      "opacity" => 1.0,
      "active" => true,
    }
    patch = { "op" => "add_clip", "track" => "V2", "clip" => clip, "created_by" => "video-broll-generate" }
    apply_patch_to_project(project, patch)
    project["assets"]["generated"] ||= []
    project["assets"]["generated"] << { "path" => output_path, "filename" => File.basename(output_path), "type" => "broll", "duration" => clip_duration }
    render = render_timeline_video(project_dir, project)

    { message: "✅ B-roll 已生成并放入 V2 轨：#{fmt_dur(start_time)} - #{fmt_dur(start_time + clip_duration)}", broll: clip, render: render, error: false }
  end

  def first_clip(project, track_id)
    track = project.dig("timeline", "tracks")&.find { |t| t["id"] == track_id }
    track && (track["clips"] || []).find { |clip| clip["active"] != false }
  end

  def timeline_render_duration(project)
    (project.dig("timeline", "effective_duration") || project.dig("timeline", "duration") || project.dig("assets", "video", 0, "duration") || 0).to_f
  end

  def synth_music_bed(output_path, duration)
    d = [duration.to_f, 1.0].max.round(3)
    fade_out = [d - 1.0, 0].max.round(3)
    filter = "[0:a][1:a][2:a]amix=inputs=3:duration=longest,volume=0.22,afade=t=in:st=0:d=0.8,afade=t=out:st=#{fade_out}:d=0.8"
    cmd = [
      ffmpeg_bin, "-y",
      "-f", "lavfi", "-i", "sine=frequency=196:duration=#{d}",
      "-f", "lavfi", "-i", "sine=frequency=247:duration=#{d}",
      "-f", "lavfi", "-i", "sine=frequency=330:duration=#{d}",
      "-filter_complex", filter,
      "-c:a", "aac", "-b:a", "128k", output_path,
    ]
    _, _, status = Open3.capture3(*cmd)
    status.success? && File.file?(output_path)
  rescue
    false
  end

  def voiceover_text(command, project)
    text = command.to_s
      .sub(/.*?(配音|旁白|voiceover|朗读|生成语音|tts)[:：\s]*/i, "")
      .strip
    return text unless text.empty?

    transcript_path = project.dig("media_index", "transcript")
    if transcript_path && File.file?(transcript_path)
      transcript = JSON.parse(File.read(transcript_path)) rescue nil
      sample = (transcript && transcript["segments"] || []).first(2).map { |s| s["text"] }.join(" ").strip
      return sample unless sample.empty?
    end
    project["name"].to_s.strip
  end

  def broll_start_time(project, total_duration)
    transcript_path = project.dig("media_index", "transcript")
    if transcript_path && File.file?(transcript_path)
      transcript = JSON.parse(File.read(transcript_path)) rescue nil
      seg = (transcript && transcript["segments"] || []).find { |s| s["start"].to_f > 1.0 }
      return [seg["start"].to_f, [total_duration - 1.0, 0].max].min.round(3) if seg
    end
    total_duration > 8 ? 2.0 : 0.0
  end

  def scene_ranges_from_boundaries(boundaries, duration)
    points = ([0.0] + boundaries + [duration.to_f]).uniq.sort
    scenes = []
    points.each_cons(2).with_index do |(start_time, end_time), idx|
      next unless end_time > start_time + 0.05
      scenes << {
        "id" => "scene_#{idx + 1}",
        "start" => start_time.round(3),
        "end" => end_time.round(3),
        "duration" => (end_time - start_time).round(3),
      }
    end
    scenes.empty? ? [{ "id" => "scene_1", "start" => 0.0, "end" => duration.to_f.round(3), "duration" => duration.to_f.round(3) }] : scenes
  end

  def extract_highlights(project, duration)
    transcript_path = project.dig("media_index", "transcript")
    transcript = transcript_path && File.file?(transcript_path) ? (JSON.parse(File.read(transcript_path)) rescue nil) : nil
    segments = transcript ? (transcript["segments"] || []) : []
    highlights = transcript_highlights(segments, duration)
    highlights = scene_highlights(project.dig("media_index", "scenes") || [], duration) if highlights.empty?
    highlights = [{ "start" => 0.0, "end" => [duration, 12.0].min.round(3), "reason" => "fallback opening highlight", "score" => 0.5, "text_preview" => "" }] if highlights.empty?
    merge_highlights(highlights, duration).first(5)
  end

  def transcript_highlights(segments, duration)
    scored = (segments || []).map do |seg|
      start_time = seg["start"].to_f
      end_time = seg["end"].to_f
      text = seg["text"].to_s.strip
      len = text.gsub(/\s+/, "").length
      dur = [end_time - start_time, 0.1].max
      keyword_bonus = text.match?(/关键|重要|核心|结论|建议|原因|方法|增长|机会|问题|但是|所以|because|important|key|growth|problem|solution/i) ? 1.5 : 0.0
      score = (len / dur / 18.0) + keyword_bonus + (text.include?("？") || text.include?("?") ? 0.5 : 0.0)
      {
        "start" => [start_time - 0.25, 0].max.round(3),
        "end" => [end_time + 0.25, duration].min.round(3),
        "reason" => keyword_bonus.positive? ? "信息密度高，含关键表达" : "信息密度较高",
        "score" => score.round(3),
        "text_preview" => text.slice(0, 120),
      }
    end.select { |h| h["end"].to_f > h["start"].to_f + 0.35 }

    scored.sort_by { |h| -h["score"].to_f }.first(5).sort_by { |h| h["start"].to_f }
  end

  def scene_highlights(scenes, duration)
    (scenes || []).first(4).map.with_index do |scene, idx|
      start_time = scene["start"].to_f
      end_time = [scene["end"].to_f, start_time + 15.0, duration].min
      next unless end_time > start_time + 0.35
      {
        "start" => start_time.round(3),
        "end" => end_time.round(3),
        "reason" => "代表性场景 ##{idx + 1}",
        "score" => (0.7 - idx * 0.05).round(3),
        "text_preview" => "",
      }
    end.compact
  end

  def merge_highlights(highlights, duration)
    sorted = highlights.sort_by { |h| h["start"].to_f }
    merged = []
    sorted.each do |h|
      h["start"] = [[h["start"].to_f, 0].max, duration].min.round(3)
      h["end"] = [[h["end"].to_f, 0].max, duration].min.round(3)
      next unless h["end"].to_f > h["start"].to_f + 0.05

      if merged.empty? || h["start"].to_f > merged[-1]["end"].to_f + 0.25
        merged << h
      else
        merged[-1]["end"] = [merged[-1]["end"].to_f, h["end"].to_f].max.round(3)
        merged[-1]["score"] = [merged[-1]["score"].to_f, h["score"].to_f].max.round(3)
        merged[-1]["reason"] = [merged[-1]["reason"], h["reason"]].compact.uniq.join(" + ")
      end
    end
    merged
  end

  def non_highlight_cuts(highlights, duration)
    cuts = []
    cursor = 0.0
    highlights.sort_by { |h| h["start"].to_f }.each do |h|
      start_time = h["start"].to_f
      end_time = h["end"].to_f
      cuts << { "start" => cursor.round(3), "end" => start_time.round(3), "reason" => "non-highlight gap" } if start_time > cursor + 0.05
      cursor = [cursor, end_time].max
    end
    cuts << { "start" => cursor.round(3), "end" => duration.to_f.round(3), "reason" => "non-highlight gap" } if duration > cursor + 0.05
    cuts.reject { |cut| cut["end"].to_f - cut["start"].to_f < 0.1 }
  end

  def broll_prompt(command, project)
    text = command.to_s
      .sub(/.*?(b-?roll|补镜头|插入画面|补画面|加画面|加素材|illustrate)[:：\s]*/i, "")
      .strip
    return text unless text.empty?
    project["name"].to_s.empty? ? "ChatCutPro b-roll" : project["name"].to_s
  end

  def synth_broll_video(project_dir, project, output_path, duration, prompt)
    width, height = timeline_dimensions(project)
    label = "B-ROLL"
    escaped_label = ffmpeg_drawtext_escape(label)
    escaped_prompt = ffmpeg_drawtext_escape(prompt.to_s.slice(0, 48))
    filter = [
      "format=yuv420p",
      "drawbox=x=0:y=0:w=iw:h=ih:color=0x111827@0.42:t=fill",
      "drawbox=x=80:y=80:w=iw-160:h=ih-160:color=white@0.18:t=4",
      "drawtext=text='#{escaped_label}':x=(w-text_w)/2:y=(h-text_h)/2-42:fontsize=58:fontcolor=white:box=1:boxcolor=black@0.25:boxborderw=18",
      "drawtext=text='#{escaped_prompt}':x=(w-text_w)/2:y=(h-text_h)/2+52:fontsize=28:fontcolor=white",
    ].join(",")
    args = [
      ffmpeg_bin, "-y",
      "-f", "lavfi", "-i", "testsrc2=size=#{width}x#{height}:rate=30:duration=#{duration}",
      "-vf", filter,
      "-an", "-c:v", "libx264", "-pix_fmt", "yuv420p", output_path,
    ]
    _, _, status = Open3.capture3(*args)
    return true if status.success? && File.file?(output_path)

    fallback_args = [
      ffmpeg_bin, "-y",
      "-f", "lavfi", "-i", "testsrc2=size=#{width}x#{height}:rate=30:duration=#{duration}",
      "-an", "-c:v", "libx264", "-pix_fmt", "yuv420p", output_path,
    ]
    _, _, fallback_status = Open3.capture3(*fallback_args)
    fallback_status.success? && File.file?(output_path)
  rescue
    false
  end

  def timeline_dimensions(project)
    width = project.dig("timeline", "resolution", "width") || project.dig("assets", "video", 0, "width") || 1920
    height = project.dig("timeline", "resolution", "height") || project.dig("assets", "video", 0, "height") || 1080
    [width.to_i.positive? ? width.to_i : 1920, height.to_i.positive? ? height.to_i : 1080]
  end

  def ffmpeg_drawtext_escape(value)
    value.to_s.gsub("\\", "\\\\\\").gsub(":", "\\:").gsub("'", "\\\\'").gsub("%", "\\%")
  end

  # ── 导出 ──────────────────────────────────────────────
  def do_export(project_dir, video_path, project, ratio)
    input = latest_video(project_dir, video_path)
    output_name = "export_#{ratio.gsub(':', 'x')}.mp4"
    output_path = File.join(project_dir, "exports", output_name)
    FileUtils.mkdir_p(File.dirname(output_path))

    dims = case ratio
    when "9:16" then "1080:1920"
    when "1:1"  then "1080:1080"
    else "1920:1080"
    end

    filter = "scale=#{dims}:force_original_aspect_ratio=decrease,pad=#{dims}:(ow-iw)/2:(oh-ih)/2:black"
    styled_ass = File.join(project_dir, "captions_styled.ass")
    srt = File.join(project_dir, "captions.srt")
    if File.exist?(styled_ass) && !timeline_render_includes_captions?(project, input)
      filter += ",ass='#{styled_ass}'"
    elsif File.exist?(srt) && !timeline_render_includes_captions?(project, input)
      filter += ",subtitles='#{srt}'"
    end

    cmd = "#{ffmpeg_bin} -y -i \"#{input}\" -vf \"#{filter}\" -c:v libx264 -crf 23 -c:a aac \"#{output_path}\" 2>&1"
    _, stderr, status = Open3.capture3(cmd)

    if status.success? && File.exist?(output_path)
      size_mb = (File.size(output_path) / 1048576.0).round(1)
      { message: "✅ #{ratio} 导出完成（#{size_mb} MB）\n#{output_path}", error: false }
    else
      { message: "❌ 导出失败：#{stderr.lines.last(2).join.strip}", error: true, blocking: false }
    end
  end

  # ── HyperFrames 动效组件 ─────────────────────────────
  def do_hyperframes_motion(project_dir, video_path, project, command)
    FileUtils.mkdir_p(File.join(project_dir, "generated"))
    type = hyperframes_component_type(command)
    props = hyperframes_props(type, command, project)
    stamp = Time.now.strftime("%Y%m%d_%H%M%S")
    html_name = "hyperframes_#{type}_#{stamp}.html"
    html_path = File.join(project_dir, "generated", html_name)
    File.write(html_path, build_hyperframes_html(type, props, project))

    component = {
      "engine" => "hyperframes",
      "template" => type,
      "start" => props["start"],
      "duration" => props["duration"],
      "props" => props,
      "html_path" => html_path,
      "editable" => true,
    }

    render_path = nil
    render_path = try_hyperframes_render(project_dir, html_path, type, stamp) if command.match?(/渲染|导出|mp4|预览视频|render/)
    render_path ||= synth_motion_graphic_video(project_dir, project, type, props, stamp)
    component["render_path"] = render_path if render_path
    component["source"] = render_path if render_path
    component["timeline_start"] = props["start"]
    component["end"] = props["start"].to_f + props["duration"].to_f
    component["fit"] = "overlay"
    component["opacity"] = type == "title_card" ? 1.0 : 0.96

    patch = {
      "op" => "add_motion_graphic",
      "track" => "MG",
      "component" => component,
      "created_by" => "video-motion-generate/hyperframes",
    }
    apply_patch_to_project(project, patch)
    project["media_index"]["hyperframes"] ||= []
    project["media_index"]["hyperframes"] << component

    msg = [
      "✅ HyperFrames 动效已加入 MG 轨",
      "类型：#{type}",
      "组件：#{html_path}",
    ]
    msg << "渲染：#{render_path}" if render_path
    if render_path
      msg << "已生成可合成预览 MP4，并会进入最终成片。"
    else
      msg << "未本地渲染时仍可作为可编辑 HTML 组件继续修改。需要成片时说「渲染这个 HyperFrames 动效」。"
    end

    render = render_timeline_video(project_dir, project)
    msg << "预览已刷新。" if render[:ok]

    { message: msg.join("\n"), motion_graphics: motion_graphics_for_ui(project), error: false }
  end

  def hyperframes_component_type(command)
    cmd = command.downcase
    return "title_card" if cmd.match?(/标题卡|title.?card|片头|开场/)
    return "logo_reveal" if cmd.match?(/logo|标志/)
    return "chart" if cmd.match?(/图表|chart|数据/)
    return "cta_overlay" if cmd.match?(/cta|call.?to.?action|关注|订阅|购买/)
    return "website_video" if cmd.match?(/网站.*视频|网页.*视频|website|url/)
    "lower_third"
  end

  def hyperframes_props(type, command, project)
    duration = case type
    when "title_card" then 5.0
    when "website_video" then 8.0
    else 4.5
    end
    {
      "title" => project["name"].to_s.empty? ? "ChatCutPro" : project["name"].to_s,
      "subtitle" => command.to_s.strip.empty? ? "AI video editing agent" : command.to_s.strip,
      "brand" => "ChatCutPro",
      "accent" => "#6D5EF7",
      "background" => "#101216",
      "foreground" => "#FFFFFF",
      "start" => 1.0,
      "duration" => duration,
      "animation" => "slide_fade",
    }
  end

  def build_hyperframes_html(type, props, project)
    title = html_escape(props["title"])
    subtitle = html_escape(props["subtitle"])
    brand = html_escape(props["brand"])
    accent = html_escape(props["accent"])
    bg = html_escape(props["background"])
    fg = html_escape(props["foreground"])
    duration = props["duration"].to_f

    <<~HTML
      <!doctype html>
      <html lang="zh-CN">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>#{brand} HyperFrames #{html_escape(type)}</title>
        <style>
          :root { --accent: #{accent}; --bg: #{bg}; --fg: #{fg}; }
          * { box-sizing: border-box; }
          body {
            margin: 0;
            width: 1920px;
            height: 1080px;
            overflow: hidden;
            background: transparent;
            font-family: Inter, "SF Pro Display", "Noto Sans SC", Arial, sans-serif;
            color: var(--fg);
          }
          [data-composition-id] {
            position: relative;
            width: 1920px;
            height: 1080px;
            overflow: hidden;
          }
          .clip {
            position: absolute;
            inset: 0;
          }
          .lower-third {
            left: 116px;
            right: auto;
            top: auto;
            bottom: 120px;
            width: 760px;
            height: 184px;
            padding: 32px 38px;
            border-radius: 18px;
            background: linear-gradient(135deg, rgba(16,18,22,.88), rgba(16,18,22,.58));
            border: 2px solid rgba(255,255,255,.18);
            box-shadow: 0 30px 80px rgba(0,0,0,.32);
            animation: lowerIn 900ms cubic-bezier(.2,.9,.2,1) both;
          }
          .title-card {
            display: grid;
            place-items: center;
            padding: 160px;
            background:
              radial-gradient(circle at 18% 24%, color-mix(in srgb, var(--accent), transparent 34%), transparent 32%),
              linear-gradient(135deg, var(--bg), #05060a);
          }
          .title-stack { max-width: 1180px; }
          .eyebrow {
            display: inline-flex;
            align-items: center;
            height: 42px;
            padding: 0 18px;
            border-radius: 999px;
            background: color-mix(in srgb, var(--accent), transparent 18%);
            color: white;
            font-size: 24px;
            font-weight: 760;
            margin-bottom: 26px;
          }
          h1 {
            margin: 0;
            font-size: 76px;
            line-height: 1.02;
            letter-spacing: 0;
            font-weight: 850;
          }
          p {
            margin: 18px 0 0;
            font-size: 34px;
            line-height: 1.25;
            color: rgba(255,255,255,.78);
          }
          .accent-line {
            position: absolute;
            left: 0;
            bottom: 0;
            height: 8px;
            width: 100%;
            background: var(--accent);
            transform-origin: left center;
            animation: lineGrow #{[duration, 1.0].max}s linear both;
          }
          @keyframes lowerIn {
            from { opacity: 0; transform: translate3d(-80px, 22px, 0) scale(.98); filter: blur(8px); }
            to { opacity: 1; transform: translate3d(0, 0, 0) scale(1); filter: blur(0); }
          }
          @keyframes lineGrow {
            from { transform: scaleX(0); }
            to { transform: scaleX(1); }
          }
        </style>
      </head>
      <body>
        <main data-composition-id="chatcutpro-#{html_escape(type)}" data-duration="#{duration}" data-fps="30" data-width="1920" data-height="1080">
          <section class="clip #{type == 'lower_third' ? 'lower-third' : 'title-card'}" data-start="0" data-duration="#{duration}">
            <div class="title-stack">
              <div class="eyebrow">#{brand}</div>
              <h1>#{title}</h1>
              <p>#{subtitle}</p>
            </div>
            <div class="accent-line"></div>
          </section>
        </main>
        <script>
          window.__chatcutproHyperFrames = #{JSON.generate({ type: type, props: props, project_id: project["id"] })};
        </script>
      </body>
      </html>
    HTML
  end

  def try_hyperframes_render(project_dir, html_path, type, stamp)
    return nil unless node22_ok? && command_ok?("npx")

    hf_dir = File.join(project_dir, "generated", "hyperframes_#{type}_#{stamp}")
    FileUtils.mkdir_p(hf_dir)
    FileUtils.cp(html_path, File.join(hf_dir, "index.html"))
    File.write(File.join(hf_dir, "meta.json"), JSON.pretty_generate({ "name" => "chatcutpro-#{type}", "duration" => 5, "fps" => 30 }))

    begin
      Timeout.timeout(120) do
        Open3.capture3("#{resolve_cmd('npx')} --yes hyperframes render 2>&1", chdir: hf_dir)
      end
    rescue
      return nil
    end

    candidates = Dir.glob(File.join(hf_dir, "**", "*.mp4")).select { |path| File.file?(path) }
    return nil if candidates.empty?

    out = File.join(project_dir, "generated", "hyperframes_#{type}_#{stamp}.mp4")
    FileUtils.cp(candidates.max_by { |path| File.mtime(path) }, out)
    out
  end

  def synth_motion_graphic_video(project_dir, project, type, props, stamp)
    FileUtils.mkdir_p(File.join(project_dir, "generated"))
    width, height = timeline_dimensions(project)
    duration = [props["duration"].to_f, 1.0].max.round(3)
    output_path = File.join(project_dir, "generated", "hyperframes_#{type}_#{stamp}_fallback.mov")
    title = ffmpeg_drawtext_escape(props["title"].to_s.slice(0, 42))
    subtitle = ffmpeg_drawtext_escape(props["subtitle"].to_s.slice(0, 64))
    brand = ffmpeg_drawtext_escape(props["brand"].to_s.slice(0, 24))
    accent = props["accent"].to_s.gsub("#", "0x")
    lower_w = [[820, width - 144].min, 180].max
    lower_h = [[156, height - 48].min, 84].max
    lower_x = [[72, (width - lower_w) / 2].min, 20].max
    lower_y = [height - lower_h - 76, 20].max
    line_y = lower_y + lower_h - 10
    brand_y = lower_y + 24
    title_y = lower_y + 62
    subtitle_y = lower_y + 108

    filters = if type == "title_card"
      [
        "format=rgba",
        "drawbox=x=0:y=0:w=iw:h=ih:color=0x101216@0.92:t=fill",
        "drawbox=x=0:y=h-12:w=iw:h=12:color=#{accent}@1:t=fill",
        "drawtext=text='#{brand}':x=(w-text_w)/2:y=h*0.30:fontsize=36:fontcolor=white:box=1:boxcolor=#{accent}@0.85:boxborderw=18",
        "drawtext=text='#{title}':x=(w-text_w)/2:y=h*0.45:fontsize=68:fontcolor=white",
        "drawtext=text='#{subtitle}':x=(w-text_w)/2:y=h*0.57:fontsize=30:fontcolor=white@0.82",
      ]
    else
      [
        "format=rgba",
        "drawbox=x=#{lower_x}:y=#{lower_y}:w=#{lower_w}:h=#{lower_h}:color=0x101216@0.72:t=fill",
        "drawbox=x=#{lower_x}:y=#{line_y}:w=#{lower_w}:h=8:color=#{accent}@1:t=fill",
        "drawtext=text='#{brand}':x=#{lower_x + 34}:y=#{brand_y}:fontsize=24:fontcolor=#{accent}",
        "drawtext=text='#{title}':x=#{lower_x + 34}:y=#{title_y}:fontsize=38:fontcolor=white",
        "drawtext=text='#{subtitle}':x=#{lower_x + 34}:y=#{subtitle_y}:fontsize=22:fontcolor=white@0.82",
      ]
    end

    args = [
      ffmpeg_bin, "-y",
      "-f", "lavfi", "-i", "color=c=black@0.0:s=#{width}x#{height}:rate=30:d=#{duration}",
      "-vf", filters.join(","),
      "-an", "-c:v", "qtrle", "-pix_fmt", "argb", output_path,
    ]
    _, _, status = Open3.capture3(*args)
    status.success? && File.file?(output_path) ? output_path : nil
  rescue
    nil
  end

  def motion_graphics_for_ui(project)
    track = project.dig("timeline", "tracks")&.find { |t| t["id"] == "MG" }
    track ? (track["clips"] || []) : []
  end

  # ── 报告 ──────────────────────────────────────────────
  def do_report(project_dir, project)
    original_dur = project.dig("assets", "video", 0, "duration") || 0
    silences = project.dig("media_index", "silences") || []
    fillers = project.dig("media_index", "fillers") || []
    transcript_path = project.dig("media_index", "transcript")
    transcript = transcript_path && File.file?(transcript_path) ? (JSON.parse(File.read(transcript_path)) rescue nil) : nil
    words = transcript ? (transcript["words"] || []) : []
    silence_saved = silences.sum { |s| s["end"].to_f - s["start"].to_f }.round(1)
    filler_saved = fillers.sum { |f| f["end"].to_f - f["start"].to_f }.round(1)
    total_saved = silence_saved + filler_saved
    exports = Dir.glob(File.join(project_dir, "exports", "*")).select { |path| File.file?(path) }
    generated = Dir.glob(File.join(project_dir, "generated", "*")).select { |path| File.file?(path) }
    final_video = latest_video(project_dir, project.dig("assets", "video", 0, "path"))
    final_dur = final_video && File.file?(final_video) ? probe_duration(final_video) : nil

    lines = [
      "# 剪辑报告",
      "",
      "## 基本信息",
      "- 项目：#{project['name']}",
      "- 原始时长：#{fmt_dur(original_dur)}",
      "- 当前成片时长：#{fmt_dur(final_dur || original_dur)}",
      "- 当前版本：##{project['current_version']}",
      "- 已完成步骤：#{(project['steps_completed'] || []).join(', ')}",
      "",
    ]

    if total_saved > 0
      pct = original_dur > 0 ? ((total_saved / original_dur) * 100).round(1) : 0
      lines << "## 时间节省"
      lines << "- 总计：#{total_saved}s（#{pct}%）"
      lines << "- 停顿：#{silence_saved}s（#{silences.length} 处）" if silence_saved > 0
      lines << "- 口癖：#{filler_saved}s（#{fillers.length} 处）" if filler_saved > 0
      lines << ""
    end

    if words.any?
      filler_rank = (project.dig("media_index", "fillers") || []).map { |w| w["word"].to_s.strip }.reject(&:empty?).each_with_object(Hash.new(0)) { |w, h| h[w] += 1 }.sort_by { |_, c| -c }.first(8)
      lines << "## Transcript"
      lines << "- 词数：#{words.length}"
      lines << "- 段落数：#{transcript['segments']&.length || 0}"
      lines << "- 语言：#{transcript['language'] || 'unknown'}"
      if filler_rank.any?
        lines << ""
        lines << "## 口癖词排行"
        filler_rank.each_with_index { |(word, count), idx| lines << "#{idx + 1}. #{word} ×#{count}" }
      end
      lines << ""
    end

    if (project["edit_decisions"] || []).any?
      lines << "## 操作明细"
      lines << "| 版本/patch | 操作 | 摘要 | 节省 |"
      lines << "|---|---|---|---:|"
      (project["edit_decisions"] || []).each do |d|
        patch_id = d["patch_id"] || "v#{d["version_id"]}"
        lines << "| #{patch_id} | #{d["op"]} | #{d["summary"]} | #{d["saved_seconds"].to_f.round(1)}s |"
      end
      lines << ""
    end

    if exports.any? || generated.any?
      lines << "## 输出文件"
      (exports + generated).each do |path|
        lines << "- #{File.basename(path)} (#{(File.size(path) / 1048576.0).round(1)} MB)"
      end
      lines << ""
    end

    lines << "## 下一步"
    lines << "- 继续微调：说「回滚」「对比版本」「加动效」"
    lines << "- 交付：说「导出全部」生成完整项目包"
    report = lines.join("\n")
    File.write(File.join(project_dir, "cut_report.md"), report)
    { message: report, report_path: File.join(project_dir, "cut_report.md"), error: false }
  end

  def do_export_bundle(project_dir, project)
    bundle = build_export_bundle(project_dir, project)
    { message: "✅ 项目交付包已生成\n目录：#{bundle[:bundle_dir]}\n文件数：#{bundle[:files].length}", bundle: bundle, error: false }
  end

  def build_export_bundle(project_dir, project)
    bundle_dir = File.join(project_dir, "export_bundle")
    FileUtils.rm_rf(bundle_dir)
    FileUtils.mkdir_p(bundle_dir)

    ensure_transcript_text(project_dir, project)
    do_report(project_dir, project) unless File.file?(File.join(project_dir, "cut_report.md"))
    save_project(project_dir, project)

    manifest = {
      "project_id" => project["id"],
      "project_name" => project["name"],
      "created_at" => project["created_at"],
      "exported_at" => Time.now.iso8601,
      "current_version" => project["current_version"],
      "files" => [],
    }

    required = {
      "project_meta.json" => File.join(project_dir, "project.json"),
      "timeline.json" => File.join(project_dir, "timeline.json"),
      "patches.json" => File.join(project_dir, "patches.json"),
      "edit_decisions.json" => File.join(project_dir, "edit_decisions.json"),
      "cut_report.md" => File.join(project_dir, "cut_report.md"),
      "transcript.json" => File.join(project_dir, "transcript.json"),
      "transcript.txt" => File.join(project_dir, "transcript.txt"),
      "captions.srt" => File.join(project_dir, "captions.srt"),
      "captions.ass" => File.join(project_dir, "captions.ass"),
      "captions_styled.ass" => File.join(project_dir, "captions_styled.ass"),
    }

    required.each do |name, source|
      next unless File.file?(source)
      copy_into_bundle(source, File.join(bundle_dir, name), manifest)
    end

    Dir.glob(File.join(project_dir, "exports", "*")).select { |path| File.file?(path) }.each do |path|
      name = case File.basename(path)
      when "export_16x9.mp4" then "final_16x9.mp4"
      when "export_9x16.mp4" then "final_9x16.mp4"
      else File.basename(path)
      end
      copy_into_bundle(path, File.join(bundle_dir, name), manifest)
    end

    generated_dir = File.join(bundle_dir, "generated")
    Dir.glob(File.join(project_dir, "generated", "*")).select { |path| File.file?(path) }.each do |path|
      copy_into_bundle(path, File.join(generated_dir, File.basename(path)), manifest)
    end

    write_json_file(File.join(bundle_dir, "bundle_manifest.json"), manifest)
    zip_path = zip_export_bundle(project_dir, bundle_dir)
    project["assets"]["generated"] ||= []
    project["assets"]["generated"] << { "path" => zip_path, "filename" => File.basename(zip_path), "type" => "export_bundle" } if zip_path

    {
      bundle_dir: bundle_dir,
      zip_path: zip_path,
      files: manifest["files"],
    }
  end

  def copy_into_bundle(source, dest, manifest)
    FileUtils.mkdir_p(File.dirname(dest))
    FileUtils.cp(source, dest)
    manifest["files"] << {
      "name" => dest.sub(%r{\A#{Regexp.escape(File.dirname(dest).sub(%r{/generated\z}, ""))}/?}, ""),
      "source" => source,
      "size_mb" => (File.size(dest) / 1048576.0).round(3),
    }
  end

  def zip_export_bundle(project_dir, bundle_dir)
    zip_bin = resolve_cmd("zip")
    return nil unless system("#{zip_bin} -v >/dev/null 2>&1")

    zip_path = File.join(project_dir, "exports", "chatcut_export_bundle.zip")
    FileUtils.rm_f(zip_path)
    _, _, status = Open3.capture3("#{zip_bin} -qr \"#{zip_path}\" \"#{File.basename(bundle_dir)}\"", chdir: File.dirname(bundle_dir))
    status.success? && File.file?(zip_path) ? zip_path : nil
  rescue
    nil
  end

  def ensure_transcript_text(project_dir, project)
    transcript_path = project.dig("media_index", "transcript")
    transcript_path ||= File.join(project_dir, "transcript.json")
    return unless File.file?(transcript_path)

    transcript = JSON.parse(File.read(transcript_path)) rescue nil
    return unless transcript

    lines = (transcript["segments"] || []).map do |s|
      "[#{fmt_dur(s["start"].to_f)} - #{fmt_dur(s["end"].to_f)}] #{s["text"]}"
    end
    File.write(File.join(project_dir, "transcript.txt"), lines.join("\n"))
  end

  def do_save_version(project)
    save_version(project, "自动精剪")
    { message: "✅ 版本 ##{project['current_version']} 已保存", error: false }
  end

  def do_rollback(project_dir, project)
    target = (project["current_version"] || 1) - 1
    return { message: "已是最初版本", error: false } if target < 0
    rollback_to_version(project, target)
    render_timeline_video(project_dir, project)
    { message: "✅ 已回滚到版本 ##{target}", error: false }
  end

  def do_version_info(project)
    versions = project["versions"] || []
    lines = ["📌 版本历史（当前：##{project['current_version']}）"]
    versions.each { |v| lines << "  ##{v['version_id']} #{v['label']}#{v['version_id'] == project['current_version'] ? ' ← 当前' : ''}" }
    { message: lines.join("\n"), error: false }
  end

  # ════════════════════════════════════════════════════════════════
  # Utility
  # ════════════════════════════════════════════════════════════════

  def probe_video(path)
    stdout, _, status = Open3.capture3("#{ffprobe_bin} -v quiet -print_format json -show_format -show_streams \"#{path}\" 2>&1")
    return { duration: nil, duration_str: nil, resolution: nil, fps: nil, codec: nil, width: nil, height: nil } unless status.success?
    info = JSON.parse(stdout) rescue {}
    duration = info.dig("format", "duration")&.to_f
    vs = (info["streams"] || []).find { |s| s["codec_type"] == "video" }
    w = vs&.dig("width")
    h = vs&.dig("height")
    {
      duration: duration,
      duration_str: duration ? fmt_dur(duration) : nil,
      resolution: (w && h) ? "#{w}x#{h}" : nil,
      width: w, height: h,
      fps: vs&.dig("r_frame_rate")&.then { |r| Rational(r).to_f.round(2) rescue nil },
      codec: vs&.dig("codec_name"),
    }
  rescue
    { duration: nil, duration_str: nil, resolution: nil, fps: nil, codec: nil, width: nil, height: nil }
  end

  def latest_video(project_dir, original)
    candidates = ["timeline_render.mp4", "filler_cut.mp4", "silence_cut.mp4"].map { |f| File.join(project_dir, f) }
    candidates.find { |f| File.exist?(f) } || original
  end

  def render_timeline_video(project_dir, project)
    original = project.dig("assets", "video", 0, "path")
    return { ok: false, message: "missing original video" } unless original && File.file?(original)

    cut_ranges = timeline_cut_ranges(project)
    output_path = File.join(project_dir, "timeline_render.mp4")
    suffix = SecureRandom.hex(4)
    base_path = File.join(project_dir, "_timeline_base_#{suffix}.mp4")
    visual_path = File.join(project_dir, "_timeline_visual_#{suffix}.mp4")
    video_path = File.join(project_dir, "_timeline_video_#{suffix}.mp4")
    mixed_path = File.join(project_dir, "_timeline_mixed_#{suffix}.mp4")
    if cut_ranges.empty?
      FileUtils.cp(original, base_path)
    else
      cut_with_ffmpeg(original, cut_ranges, base_path, project_dir)
    end

    visual_applied = false
    if File.file?(base_path) && timeline_visual_clips(project).any?
      visual_applied = overlay_visual_clips(project_dir, project, base_path, visual_path)
      FileUtils.cp(base_path, visual_path) unless visual_applied
    elsif File.file?(base_path)
      FileUtils.cp(base_path, visual_path)
    end

    subtitle_path = preferred_subtitle_path(project_dir)
    captions_applied = false
    if subtitle_path && File.file?(visual_path)
      captions_applied = overlay_subtitles(visual_path, subtitle_path, video_path)
      FileUtils.cp(visual_path, video_path) unless captions_applied
    elsif File.file?(visual_path)
      FileUtils.cp(visual_path, video_path)
    end

    audio_mixed = false
    if File.file?(video_path) && timeline_audio_mix_needed?(project)
      audio_mixed = mix_timeline_audio(project_dir, project, video_path, mixed_path)
      FileUtils.cp(audio_mixed ? mixed_path : video_path, output_path)
    elsif File.file?(video_path)
      FileUtils.cp(video_path, output_path)
    end
    [base_path, visual_path, video_path, mixed_path].each { |path| FileUtils.rm_f(path) }

    ok = File.file?(output_path)
    project["media_index"] ||= {}
    project["media_index"]["timeline_render"] = {
      "path" => output_path,
      "includes_visual_overlays" => visual_applied,
      "includes_captions" => captions_applied,
      "includes_audio_mix" => audio_mixed,
      "cut_count" => cut_ranges.length,
      "updated_at" => Time.now.iso8601,
    } if ok

    { ok: ok, output_file: ok ? output_path : nil, cut_count: cut_ranges.length, includes_visual_overlays: visual_applied, includes_captions: captions_applied, includes_audio_mix: audio_mixed }
  end

  def timeline_cut_ranges(project)
    timeline_cut_ranges_from_timeline(project["timeline"] || {})
  end

  def timeline_cut_ranges_from_timeline(timeline)
    tracks = timeline["tracks"] || []
    ranges = []
    tracks.select { |track| %w[V1 A1].include?(track["id"]) }.each do |track|
      (track["clips"] || []).each do |clip|
        (clip["cut_regions"] || []).each do |region|
          s = region["start"].to_f
          e = region["end"].to_f
          ranges << { "start" => s, "end" => e, "reason" => region["reason"] } if e > s
        end
      end
    end
    merge_cut_ranges(ranges)
  end

  def preferred_subtitle_path(project_dir)
    [File.join(project_dir, "captions_styled.ass"), File.join(project_dir, "captions.ass"), File.join(project_dir, "captions.srt")].find { |path| File.file?(path) }
  end

  def overlay_subtitles(input_path, subtitle_path, output_path)
    filter_name = File.extname(subtitle_path).downcase == ".srt" ? "subtitles" : "ass"
    escaped = subtitle_path.gsub("\\", "\\\\\\").gsub("'", "\\\\'")
    cmd = "#{ffmpeg_bin} -y -i \"#{input_path}\" -vf \"#{filter_name}='#{escaped}'\" -c:v libx264 -crf 23 -c:a aac \"#{output_path}\" 2>&1"
    _, _, status = Open3.capture3(cmd)
    status.success? && File.file?(output_path)
  rescue
    false
  end

  def overlay_visual_clips(project_dir, project, input_path, output_path)
    clips = timeline_visual_clips(project).map do |clip|
      source = resolve_timeline_source(project_dir, clip["render_path"] || clip["source"] || clip["path"])
      source && File.file?(source) ? clip.merge("_resolved_source" => source) : nil
    end.compact
    return false if clips.empty?

    width, height = timeline_dimensions(project)
    args = [ffmpeg_bin, "-y", "-i", input_path]
    clips.each { |clip| args += ["-i", clip["_resolved_source"]] }

    parts = ["[0:v]setpts=PTS-STARTPTS[v0]"]
    last_label = "v0"
    clips.each_with_index do |clip, idx|
      input_idx = idx + 1
      start_time = (clip["timeline_start"] || clip["start"] || 0).to_f
      end_time = (clip["end"] || (start_time + (clip["out"] || clip["duration"] || 4).to_f)).to_f
      opacity = [[(clip["opacity"] || 1.0).to_f, 0.0].max, 1.0].min
      overlay_label = "ov#{idx}"
      out_label = "v#{idx + 1}"
      alpha_filter = opacity < 0.999 ? ",colorchannelmixer=aa=#{opacity.round(3)}" : ""
      parts << "[#{input_idx}:v]scale=#{width}:#{height}:force_original_aspect_ratio=increase,crop=#{width}:#{height},format=rgba#{alpha_filter},setpts=PTS-STARTPTS+#{start_time.round(3)}/TB[#{overlay_label}]"
      parts << "[#{last_label}][#{overlay_label}]overlay=0:0:enable='between(t,#{start_time.round(3)},#{end_time.round(3)})'[#{out_label}]"
      last_label = out_label
    end

    args += [
      "-filter_complex", parts.join(";"),
      "-map", "[#{last_label}]",
      "-map", "0:a?",
      "-c:v", "libx264",
      "-pix_fmt", "yuv420p",
      "-c:a", "copy",
      "-shortest",
      output_path,
    ]
    _, _, status = Open3.capture3(*args)
    status.success? && File.file?(output_path)
  rescue
    false
  end

  def timeline_visual_clips(project)
    tracks = project.dig("timeline", "tracks") || []
    %w[V2 MG].flat_map do |track_id|
      track = tracks.find { |t| t["id"] == track_id }
      ((track && track["clips"]) || []).select { |clip| clip["active"] != false && (clip["render_path"] || clip["source"] || clip["path"]) }
    end
  end

  def timeline_audio_mix_needed?(project)
    !audio_processing_filters(project).empty? || timeline_audio_clips(project).any?
  end

  def mix_timeline_audio(project_dir, project, video_path, output_path)
    filter_parts = []
    labels = []
    input_paths = []

    if media_has_audio?(video_path)
      filters = audio_processing_filters(project)
      chain = filters.empty? ? "[0:a]anull[a0]" : "[0:a]#{filters.join(',')}[a0]"
      filter_parts << chain
      labels << "[a0]"
    end

    timeline_audio_clips(project).each do |clip|
      source = resolve_timeline_source(project_dir, clip["source"] || clip["path"])
      next unless source && File.file?(source)

      input_paths << source
      input_index = input_paths.length
      label = "a#{input_index}"
      start_ms = (clip["timeline_start"] || clip["start"] || 0).to_f * 1000
      duration = (clip["out"] || ((clip["end"] || 0).to_f - (clip["start"] || 0).to_f)).to_f
      volume = (clip["volume"] || 1.0).to_f
      filters = []
      filters << "atrim=0:#{duration.round(3)}" if duration.positive?
      filters << "asetpts=PTS-STARTPTS"
      filters << "volume=#{volume.round(3)}"
      filters << "adelay=#{start_ms.round}:all=1" if start_ms.positive?
      filter_parts << "[#{input_index}:a]#{filters.join(',')}[#{label}]"
      labels << "[#{label}]"
    end

    return false if labels.empty?

    filter_parts << "#{labels.join}amix=inputs=#{labels.length}:duration=first:dropout_transition=2[aout]"
    args = [ffmpeg_bin, "-y", "-i", video_path]
    input_paths.each { |path| args += ["-i", path] }
    args += ["-filter_complex", filter_parts.join(";"), "-map", "0:v", "-map", "[aout]", "-c:v", "copy", "-c:a", "aac", "-shortest", output_path]
    _, _, status = Open3.capture3(*args)
    status.success? && File.file?(output_path)
  rescue
    false
  end

  def audio_processing_filters(project)
    clip = first_clip(project, "A1") || {}
    processing = clip["audio_processing"] || {}
    filters = []
    filters << "afftdn=nf=-25" if processing["denoise"]
    if processing["normalize"]
      target = processing.dig("normalize", "target_lufs") || -16
      peak = processing.dig("normalize", "true_peak") || -1.5
      lra = processing.dig("normalize", "lra") || 11
      filters << "loudnorm=I=#{target}:TP=#{peak}:LRA=#{lra}"
    end
    filters
  end

  def timeline_audio_clips(project)
    tracks = project.dig("timeline", "tracks") || []
    tracks.select { |track| %w[MUS VO].include?(track["id"]) }.flat_map do |track|
      (track["clips"] || []).select { |clip| clip["active"] != false }
    end
  end

  def resolve_timeline_source(project_dir, source)
    return nil if source.to_s.empty?
    return source if File.file?(source)
    cleaned = source.to_s.sub(%r{\A/+}, "")
    [File.join(project_dir, cleaned), File.join(project_dir, "generated", File.basename(cleaned))].find { |path| File.file?(path) }
  end

  def media_has_audio?(path)
    stdout, _, status = Open3.capture3("#{ffprobe_bin} -v quiet -print_format json -show_streams #{Shellwords.escape(path)} 2>&1")
    return false unless status.success?
    info = JSON.parse(stdout) rescue {}
    (info["streams"] || []).any? { |stream| stream["codec_type"] == "audio" }
  rescue
    false
  end

  def timeline_render_includes_captions?(project, input_path)
    File.basename(input_path.to_s) == "timeline_render.mp4" &&
      project.dig("media_index", "timeline_render", "includes_captions")
  end

  def merge_cut_ranges(ranges)
    sorted = ranges.sort_by { |r| r["start"].to_f }
    merged = []
    sorted.each do |range|
      if merged.empty? || range["start"].to_f > merged[-1]["end"].to_f + 0.02
        merged << range.dup
      else
        merged[-1]["end"] = [merged[-1]["end"].to_f, range["end"].to_f].max
        merged[-1]["reason"] = [merged[-1]["reason"], range["reason"]].compact.join(" + ")
      end
    end
    merged
  end

  def cut_with_ffmpeg(video_path, cut_ranges, output_path, project_dir)
    duration = probe_duration(video_path) || 9999
    keep = build_keep_segments(cut_ranges, duration)
    return if keep.empty?

    suffix = SecureRandom.hex(4)
    seg_files = keep.each_with_index.map do |seg, i|
      f = File.join(project_dir, "_seg_#{suffix}_#{i}.mp4")
      dur = [seg[:end].to_f - seg[:start].to_f, 0.01].max
      Open3.capture3("#{ffmpeg_bin} -y -ss #{seg[:start]} -t #{dur} -i #{Shellwords.escape(video_path)} -map 0:v:0 -map 0:a? -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -c:a aac #{Shellwords.escape(f)} 2>&1")
      f
    end

    concat = File.join(project_dir, "_concat_#{suffix}.txt")
    File.write(concat, seg_files.select { |f| File.exist?(f) }.map { |f| "file '#{f}'" }.join("\n"))
    Open3.capture3("#{ffmpeg_bin} -y -f concat -safe 0 -i \"#{concat}\" -c copy \"#{output_path}\" 2>&1")

    seg_files.each { |f| File.delete(f) if File.exist?(f) }
    File.delete(concat) if File.exist?(concat)
  end

  def probe_duration(path)
    stdout, _, status = Open3.capture3("#{ffprobe_bin} -v quiet -print_format json -show_format \"#{path}\" 2>&1")
    return nil unless status.success?
    JSON.parse(stdout).dig("format", "duration")&.to_f rescue nil
  end

  def build_keep_segments(cut_ranges, duration)
    segs = []
    prev = 0.0
    cut_ranges.sort_by { |r| (r["start"] || r[:start]).to_f }.each do |r|
      s = (r["start"] || r[:start]).to_f
      e = (r["end"] || r[:end]).to_f
      segs << { start: prev, end: s } if s > prev + 0.05
      prev = e
    end
    segs << { start: prev, end: duration } if prev < duration - 0.05
    segs
  end

  def build_transcribe_script(audio_path)
    <<~PYTHON
import json, sys
try:
    from faster_whisper import WhisperModel
    model = WhisperModel("base", device="cpu", compute_type="int8")
    segments, info = model.transcribe("#{audio_path}", word_timestamps=True)
    result = {"language": info.language, "duration": info.duration, "segments": [], "words": []}
    for seg in segments:
        result["segments"].append({"start": round(seg.start, 3), "end": round(seg.end, 3), "text": seg.text.strip()})
        if seg.words:
            for w in seg.words:
                result["words"].append({"start": round(w.start, 3), "end": round(w.end, 3), "word": w.word.strip()})
    json.dump(result, sys.stdout, ensure_ascii=False)
except Exception as e:
    json.dump({"error": str(e)}, sys.stdout)
    PYTHON
  end

  def generate_ass(segments)
    header = <<~ASS
[Script Info]
Title: ChatCut Captions
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,2,0,2,10,10,40,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
    ASS
    events = segments.map { |s| "Dialogue: 0,#{ass_time(s['start'])},#{ass_time(s['end'])},Default,,0,0,0,,#{s['text']}" }
    header + events.join("\n") + "\n"
  end

  def srt_time(s)
    h = (s / 3600).floor; m = ((s % 3600) / 60).floor; sec = (s % 60).floor; ms = ((s % 1) * 1000).round
    format("%02d:%02d:%02d,%03d", h, m, sec, ms)
  end

  def ass_time(s)
    h = (s / 3600).floor; m = ((s % 3600) / 60).floor; sec = (s % 60).floor; cs = ((s % 1) * 100).round
    format("%d:%02d:%02d.%02d", h, m, sec, cs)
  end

  def fmt_dur(s)
    return "未知" unless s
    m = (s / 60).floor; sec = (s % 60).round(1)
    "#{m}:#{format('%04.1f', sec)}"
  end

  def html_escape(value)
    value.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;").gsub("'", "&#39;")
  end

  def assemble_response(plan, execution, project)
    results = execution[:results]
    messages = results.map { |r| r.dig(:result, :message) }.compact
    captions = results.find { |r| r.dig(:result, :captions) }&.dig(:result, :captions)
    transcript = results.find { |r| r.dig(:result, :transcript) }&.dig(:result, :transcript)
    scenes = results.find { |r| r.dig(:result, :scenes) }&.dig(:result, :scenes) || project.dig("media_index", "scenes")
    highlights = results.find { |r| r.dig(:result, :highlights) }&.dig(:result, :highlights) || project.dig("media_index", "highlights")
    bundles = results.map { |r| r.dig(:result, :bundle) }.compact

    timeline = project["timeline"] ? timeline_for_ui(project) : nil

    {
      state: execution[:has_error] ? "error" : "done",
      message: messages.join("\n\n"),
      plan: {
        command: plan[:command],
        steps: plan[:steps],
        total_steps: plan[:total],
        completed_steps: results.reject { |r| r.dig(:result, :error) }.map { |r| r[:step] },
      },
      patches_applied: (project["patches"] || []).last(8),
      edit_decisions: (project["edit_decisions"] || []).last(12),
      transcript: transcript,
      captions: captions,
      scenes: scenes,
      highlights: highlights,
      media_index: project["media_index"],
      timeline: timeline,
      version: project["current_version"],
      versions: project["versions"],
      media: media_links(project),
      motion_graphics: motion_graphics_for_ui(project),
      bundles: bundles,
      suggestions: generate_suggestions(project),
    }
  end

  def generate_suggestions(project)
    s = []
    completed = project["steps_completed"] || []
    s << "生成字幕" unless completed.include?("caption_generate")
    s << "删停顿" unless completed.include?("apply_silence_cut")
    s << "删口癖" unless completed.include?("apply_filler_cut")
    s << "HyperFrames 动效"
    s << "导出竖版" << "导出横版"
    s.first(4)
  end
end
