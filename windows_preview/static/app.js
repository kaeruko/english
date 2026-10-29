const state = {
  file: null,
  objectUrl: null,
  segments: [],
  activeSegmentIndex: -1,
  activeWordId: null,
  followPlayback: true,
  leadIn: Number(localStorage.getItem("englishReplayLeadIn") ?? 0.4),
  animationFrame: null,
};

const $ = (id) => document.getElementById(id);
const audio = $("audioElement");
const dropZone = $("dropZone");
const fileInput = $("fileInput");

function formatTime(value) {
  const safe = Number.isFinite(value) && value >= 0 ? Math.floor(value) : 0;
  const hours = Math.floor(safe / 3600);
  const minutes = Math.floor((safe % 3600) / 60);
  const seconds = safe % 60;
  return hours > 0
    ? `${hours}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`
    : `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
}

function showToast(message) {
  const toast = $("toast");
  toast.textContent = message;
  toast.classList.remove("hidden");
  window.setTimeout(() => toast.classList.add("hidden"), 7000);
}

function setStatus(message, progress, hint = "音声はこのPC内だけで処理されます。") {
  $("statusCard").classList.remove("hidden");
  $("statusText").textContent = message;
  const normalized = Math.min(1, Math.max(0, progress || 0));
  $("statusPercent").textContent = `${Math.round(normalized * 100)}%`;
  $("progressBar").style.width = `${normalized * 100}%`;
  $("statusHint").textContent = hint;
}

function currentSegmentIndex(time = audio.currentTime) {
  let fallback = -1;
  for (let index = 0; index < state.segments.length; index += 1) {
    const segment = state.segments[index];
    if (time >= segment.startTime) fallback = index;
    if (time >= segment.startTime && time < segment.endTime) return index;
  }
  return fallback;
}

function currentWord(segment, time = audio.currentTime) {
  if (!segment) return null;
  return segment.words.find((word) => time >= word.startTime && time < word.endTime) ?? null;
}

function seekTo(time, shouldPlay = true) {
  audio.currentTime = Math.max(0, Math.min(time, audio.duration || time));
  if (shouldPlay) audio.play().catch((error) => showToast(error.message));
  updatePlaybackUI();
}

function seekWithLeadIn(time) {
  seekTo(Math.max(0, time - state.leadIn), true);
}

function renderTranscript() {
  const list = $("transcriptList");
  list.replaceChildren();

  for (const segment of state.segments) {
    const card = document.createElement("article");
    card.className = "segment-card";
    card.dataset.segmentId = segment.id;

    const timeButton = document.createElement("button");
    timeButton.className = "segment-time";
    timeButton.type = "button";
    timeButton.textContent = `▶ ${formatTime(segment.startTime)}`;
    timeButton.addEventListener("click", () => seekWithLeadIn(segment.startTime));

    const words = document.createElement("div");
    words.className = "word-list";
    for (const word of segment.words) {
      const button = document.createElement("button");
      button.className = "word-button";
      button.type = "button";
      button.dataset.wordId = word.id;
      button.textContent = word.text.trim();
      button.title = `${formatTime(word.startTime)}から再生`;
      button.addEventListener("click", () => seekWithLeadIn(word.startTime));
      words.append(button);
    }

    card.append(timeButton, words);
    list.append(card);
  }
}

function updatePlaybackUI() {
  const time = audio.currentTime || 0;
  $("currentTime").textContent = formatTime(time);
  $("duration").textContent = formatTime(audio.duration || 0);
  $("timeline").max = String(audio.duration || 1);
  $("timeline").value = String(time);
  $("playButton").textContent = audio.paused ? "▶" : "Ⅱ";
  $("playButton").setAttribute("aria-label", audio.paused ? "再生" : "一時停止");

  const segmentIndex = currentSegmentIndex(time);
  const segment = state.segments[segmentIndex];
  const word = currentWord(segment, time);

  if (segmentIndex !== state.activeSegmentIndex) {
    document.querySelector(".segment-card.active")?.classList.remove("active");
    const activeCard = segment ? document.querySelector(`[data-segment-id="${segment.id}"]`) : null;
    activeCard?.classList.add("active");
    state.activeSegmentIndex = segmentIndex;
    if (state.followPlayback && activeCard) {
      activeCard.scrollIntoView({ behavior: "smooth", block: "center" });
    }
  }

  if (word?.id !== state.activeWordId) {
    document.querySelector(".word-button.active")?.classList.remove("active");
    if (word) document.querySelector(`[data-word-id="${word.id}"]`)?.classList.add("active");
    state.activeWordId = word?.id ?? null;
  }
}

function playbackLoop() {
  updatePlaybackUI();
  if (!audio.paused) state.animationFrame = requestAnimationFrame(playbackLoop);
}

async function pollJob(jobId) {
  while (true) {
    const response = await fetch(`/api/jobs/${jobId}`);
    if (!response.ok) throw new Error((await response.json()).detail || "状態を取得できませんでした。");
    const job = await response.json();
    setStatus(
      job.message,
      job.progress,
      job.status === "loading_model"
        ? "初回だけモデルをダウンロードします。ウィンドウを閉じずにお待ちください。"
        : "単語ごとの時間を解析しています。"
    );

    if (job.status === "done") return job.result;
    if (job.status === "error") throw new Error(job.error || job.message);
    await new Promise((resolve) => window.setTimeout(resolve, 800));
  }
}

async function processFile(file) {
  if (!file) return;
  state.file = file;
  if (state.objectUrl) URL.revokeObjectURL(state.objectUrl);
  state.objectUrl = URL.createObjectURL(file);
  audio.src = state.objectUrl;

  dropZone.classList.add("hidden");
  setStatus("音声を読み込んでいます…", 0);

  try {
    const response = await fetch("/api/jobs", {
      method: "POST",
      headers: {
        "Content-Type": "application/octet-stream",
        "X-Filename": encodeURIComponent(file.name),
      },
      body: file,
    });
    if (!response.ok) throw new Error((await response.json()).detail || "アップロードできませんでした。");
    const { id } = await response.json();
    const result = await pollJob(id);
    state.segments = result.segments;
    $("audioTitle").textContent = result.title || file.name;
    renderTranscript();
    $("welcomePanel").classList.add("hidden");
    $("transcriptPanel").classList.remove("hidden");
    $("playerDock").classList.remove("hidden");
    document.title = `${result.title || file.name} — English Replay`;
    updatePlaybackUI();
  } catch (error) {
    dropZone.classList.remove("hidden");
    $("statusCard").classList.add("hidden");
    showToast(error.message || String(error));
  }
}

$("chooseButton").addEventListener("click", () => fileInput.click());
fileInput.addEventListener("change", () => processFile(fileInput.files?.[0]));

for (const eventName of ["dragenter", "dragover"]) {
  dropZone.addEventListener(eventName, (event) => {
    event.preventDefault();
    dropZone.classList.add("dragging");
  });
}
for (const eventName of ["dragleave", "drop"]) {
  dropZone.addEventListener(eventName, (event) => {
    event.preventDefault();
    dropZone.classList.remove("dragging");
  });
}
dropZone.addEventListener("drop", (event) => processFile(event.dataTransfer?.files?.[0]));
dropZone.addEventListener("keydown", (event) => {
  if (event.key === "Enter" || event.key === " ") fileInput.click();
});

$("playButton").addEventListener("click", () => {
  if (audio.paused) audio.play().catch((error) => showToast(error.message));
  else audio.pause();
});
audio.addEventListener("play", () => {
  cancelAnimationFrame(state.animationFrame);
  playbackLoop();
});
audio.addEventListener("pause", updatePlaybackUI);
audio.addEventListener("loadedmetadata", updatePlaybackUI);
audio.addEventListener("ended", updatePlaybackUI);

$("timeline").addEventListener("input", (event) => seekTo(Number(event.target.value), false));
$("speedSelect").addEventListener("change", (event) => { audio.playbackRate = Number(event.target.value); });

$("replayButton").addEventListener("click", () => {
  const index = currentSegmentIndex();
  seekWithLeadIn(index >= 0 ? state.segments[index].startTime : 0);
});

$("previousButton").addEventListener("click", () => {
  const index = currentSegmentIndex();
  if (index < 0) return seekTo(0);
  const current = state.segments[index];
  const targetIndex = audio.currentTime - current.startTime > 1.5 ? index : Math.max(0, index - 1);
  seekWithLeadIn(state.segments[targetIndex].startTime);
});

$("nextButton").addEventListener("click", () => {
  const index = currentSegmentIndex();
  if (index >= 0 && index + 1 < state.segments.length) seekWithLeadIn(state.segments[index + 1].startTime);
});

$("followButton").addEventListener("click", (event) => {
  state.followPlayback = !state.followPlayback;
  event.currentTarget.classList.toggle("active", state.followPlayback);
  event.currentTarget.textContent = state.followPlayback ? "● 自動追従" : "○ 再生位置へ戻る";
  if (state.followPlayback && state.activeSegmentIndex >= 0) {
    document.querySelector(`[data-segment-id="${state.segments[state.activeSegmentIndex].id}"]`)
      ?.scrollIntoView({ behavior: "smooth", block: "center" });
  }
});

$("transcriptList").addEventListener("wheel", () => {
  if (state.followPlayback) {
    state.followPlayback = false;
    $("followButton").classList.remove("active");
    $("followButton").textContent = "○ 再生位置へ戻る";
  }
}, { passive: true });

const leadInSelect = $("leadInSelect");
leadInSelect.value = String(state.leadIn);
leadInSelect.addEventListener("change", (event) => {
  state.leadIn = Number(event.target.value);
  localStorage.setItem("englishReplayLeadIn", String(state.leadIn));
});
