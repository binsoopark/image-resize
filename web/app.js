/** @typedef {{ id: string, file: File, objectUrl: string, originalWidth: number, originalHeight: number, resultBlob: Blob | null, resultUrl: string | null, status: 'ready' | 'processing' | 'done' | 'error', error: string | null }} ImageItem */

const dropZone = document.getElementById("dropZone");
const fileInput = document.getElementById("fileInput");
const targetWidthInput = document.getElementById("targetWidth");
const targetHeightInput = document.getElementById("targetHeight");
const outputFormatSelect = document.getElementById("outputFormat");
const processBtn = document.getElementById("processBtn");
const downloadAllBtn = document.getElementById("downloadAllBtn");
const clearBtn = document.getElementById("clearBtn");
const gallery = document.getElementById("gallery");
const imageList = document.getElementById("imageList");
const fileCount = document.getElementById("fileCount");

/** @type {ImageItem[]} */
let items = [];

function showToast(message) {
  let toast = document.querySelector(".toast");
  if (!toast) {
    toast = document.createElement("div");
    toast.className = "toast";
    document.body.appendChild(toast);
  }
  toast.textContent = message;
  toast.classList.add("show");
  clearTimeout(showToast._timer);
  showToast._timer = setTimeout(() => toast.classList.remove("show"), 3200);
}

function updateButtons() {
  const hasItems = items.length > 0;
  const hasResults = items.some((item) => item.status === "done" && item.resultBlob);
  processBtn.disabled = !hasItems;
  clearBtn.disabled = !hasItems;
  downloadAllBtn.disabled = !hasResults;
}

function revokeItemUrls(item) {
  URL.revokeObjectURL(item.objectUrl);
  if (item.resultUrl) URL.revokeObjectURL(item.resultUrl);
}

function clearAll() {
  items.forEach(revokeItemUrls);
  items = [];
  imageList.innerHTML = "";
  gallery.hidden = true;
  fileCount.textContent = "0";
  updateButtons();
}

function getExtension(mime) {
  if (mime === "image/jpeg") return "jpg";
  if (mime === "image/webp") return "webp";
  return "png";
}

function outputFileName(originalName, mime) {
  const base = originalName.replace(/\.[^.]+$/, "");
  return `${base}_cropped.${getExtension(mime)}`;
}

function centerCropImage(img, targetW, targetH, mime, quality = 0.92) {
  const srcW = img.naturalWidth;
  const srcH = img.naturalHeight;

  let scale = 1;
  if (srcW < targetW || srcH < targetH) {
    scale = Math.max(targetW / srcW, targetH / srcH);
  }

  const scaledW = srcW * scale;
  const scaledH = srcH * scale;
  const cropX = (scaledW - targetW) / 2;
  const cropY = (scaledH - targetH) / 2;

  const canvas = document.createElement("canvas");
  canvas.width = targetW;
  canvas.height = targetH;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("Canvas를 사용할 수 없습니다.");

  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = "high";
  ctx.drawImage(img, 0, 0, srcW, srcH, -cropX, -cropY, scaledW, scaledH);

  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (blob) => {
        if (blob) resolve(blob);
        else reject(new Error("이미지 변환에 실패했습니다."));
      },
      mime,
      quality,
    );
  });
}

function loadImageFromUrl(url) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error("이미지를 불러올 수 없습니다."));
    img.src = url;
  });
}

function createCardElement(item) {
  const card = document.createElement("article");
  card.className = `image-card ${item.status}`;
  card.dataset.id = item.id;

  card.innerHTML = `
    <div class="preview-wrap">
      <img src="${item.resultUrl || item.objectUrl}" alt="" />
      <span class="status">${statusLabel(item)}</span>
    </div>
    <div class="card-body">
      <p class="file-name" title="${escapeHtml(item.file.name)}">${escapeHtml(item.file.name)}</p>
      <p class="meta">${item.originalWidth} × ${item.originalHeight}px</p>
      <div class="card-actions">
        <button type="button" class="btn download-one" ${item.resultBlob ? "" : "disabled"}>다운로드</button>
      </div>
    </div>
  `;

  card.querySelector(".download-one")?.addEventListener("click", () => {
    downloadSingle(item);
  });

  return card;
}

function statusLabel(item) {
  switch (item.status) {
    case "processing":
      return "처리 중";
    case "done":
      return "완료";
    case "error":
      return "오류";
    default:
      return "대기";
  }
}

function escapeHtml(text) {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function renderGallery() {
  imageList.innerHTML = "";
  items.forEach((item) => {
    imageList.appendChild(createCardElement(item));
  });
  gallery.hidden = items.length === 0;
  fileCount.textContent = String(items.length);
  updateButtons();
}

function refreshCard(item) {
  const existing = imageList.querySelector(`[data-id="${item.id}"]`);
  if (existing) existing.replaceWith(createCardElement(item));
  updateButtons();
}

async function addFiles(fileList) {
  const imageFiles = [...fileList].filter((file) => file.type.startsWith("image/"));
  if (imageFiles.length === 0) {
    showToast("이미지 파일만 추가할 수 있습니다.");
    return;
  }

  for (const file of imageFiles) {
    const objectUrl = URL.createObjectURL(file);
    try {
      const img = await loadImageFromUrl(objectUrl);
      items.push({
        id: crypto.randomUUID(),
        file,
        objectUrl,
        originalWidth: img.naturalWidth,
        originalHeight: img.naturalHeight,
        resultBlob: null,
        resultUrl: null,
        status: "ready",
        error: null,
      });
    } catch (err) {
      URL.revokeObjectURL(objectUrl);
      showToast(`${file.name}: ${err instanceof Error ? err.message : "추가 실패"}`);
    }
  }

  renderGallery();
}

function readTargetSize() {
  const w = parseInt(targetWidthInput.value, 10);
  const h = parseInt(targetHeightInput.value, 10);
  if (!Number.isFinite(w) || w < 1 || !Number.isFinite(h) || h < 1) {
    throw new Error("너비와 높이는 1 이상의 숫자여야 합니다.");
  }
  return { w, h };
}

async function processAll() {
  let target;
  try {
    target = readTargetSize();
  } catch (err) {
    showToast(err instanceof Error ? err.message : "크기 입력이 올바르지 않습니다.");
    return;
  }

  const mime = outputFormatSelect.value;
  const quality = mime === "image/png" ? undefined : 0.92;

  processBtn.disabled = true;

  for (const item of items) {
    item.status = "processing";
    item.error = null;
    if (item.resultUrl) {
      URL.revokeObjectURL(item.resultUrl);
      item.resultUrl = null;
      item.resultBlob = null;
    }
    refreshCard(item);

    try {
      const img = await loadImageFromUrl(item.objectUrl);
      const blob = await centerCropImage(img, target.w, target.h, mime, quality);
      item.resultBlob = blob;
      item.resultUrl = URL.createObjectURL(blob);
      item.status = "done";
    } catch (err) {
      item.status = "error";
      item.error = err instanceof Error ? err.message : "처리 실패";
    }

    refreshCard(item);
  }

  processBtn.disabled = false;
  showToast("모든 이미지 처리가 완료되었습니다.");
}

function triggerDownload(blob, filename) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

function downloadSingle(item) {
  if (!item.resultBlob) return;
  triggerDownload(item.resultBlob, outputFileName(item.file.name, outputFormatSelect.value));
}

async function downloadAllWithDirectoryPicker(doneItems, mime) {
  if (!("showDirectoryPicker" in window)) return false;

  let dirHandle;
  try {
    dirHandle = await window.showDirectoryPicker({
      mode: "readwrite",
      startIn: "downloads",
    });
  } catch (err) {
    if (err instanceof DOMException && err.name === "AbortError") return true;
    throw err;
  }

  for (const item of doneItems) {
    if (!item.resultBlob) continue;
    const name = outputFileName(item.file.name, mime);
    const fileHandle = await dirHandle.getFileHandle(name, { create: true });
    const writable = await fileHandle.createWritable();
    await writable.write(item.resultBlob);
    await writable.close();
  }

  showToast(`${doneItems.length}개 파일을 선택한 폴더에 저장했습니다.`);
  return true;
}

async function downloadAllAsZip(doneItems, mime) {
  if (typeof JSZip === "undefined") {
    for (const item of doneItems) {
      downloadSingle(item);
      await new Promise((r) => setTimeout(r, 200));
    }
    showToast(`${doneItems.length}개 파일을 순차 다운로드했습니다.`);
    return;
  }

  const zip = new JSZip();
  for (const item of doneItems) {
    if (!item.resultBlob) continue;
    zip.file(outputFileName(item.file.name, mime), item.resultBlob);
  }

  const zipBlob = await zip.generateAsync({ type: "blob" });
  triggerDownload(zipBlob, "cropped-images.zip");
  showToast("ZIP 파일로 다운로드했습니다.");
}

async function downloadAll() {
  const doneItems = items.filter((item) => item.status === "done" && item.resultBlob);
  if (doneItems.length === 0) return;

  const mime = outputFormatSelect.value;

  try {
    const usedPicker = await downloadAllWithDirectoryPicker(doneItems, mime);
    if (usedPicker) return;
  } catch (err) {
    console.warn("Directory picker failed, falling back to zip:", err);
  }

  await downloadAllAsZip(doneItems, mime);
}

dropZone.addEventListener("click", () => fileInput.click());
dropZone.addEventListener("keydown", (e) => {
  if (e.key === "Enter" || e.key === " ") {
    e.preventDefault();
    fileInput.click();
  }
});

fileInput.addEventListener("change", () => {
  if (fileInput.files?.length) {
    addFiles(fileInput.files);
    fileInput.value = "";
  }
});

["dragenter", "dragover"].forEach((eventName) => {
  dropZone.addEventListener(eventName, (e) => {
    e.preventDefault();
    e.stopPropagation();
    dropZone.classList.add("drag-over");
  });
});

["dragleave", "drop"].forEach((eventName) => {
  dropZone.addEventListener(eventName, (e) => {
    e.preventDefault();
    e.stopPropagation();
    dropZone.classList.remove("drag-over");
  });
});

dropZone.addEventListener("drop", (e) => {
  const files = e.dataTransfer?.files;
  if (files?.length) addFiles(files);
});

document.body.addEventListener("dragover", (e) => e.preventDefault());
document.body.addEventListener("drop", (e) => {
  if (!dropZone.contains(e.target)) e.preventDefault();
});

processBtn.addEventListener("click", processAll);
downloadAllBtn.addEventListener("click", downloadAll);
clearBtn.addEventListener("click", clearAll);
